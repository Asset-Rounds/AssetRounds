import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V9_18PackLifecycleIntegrationTests: XCTestCase {
    func testV23P03C39WorkflowBindingKeepsEndedDispositionTyped() throws {
        let event = try AssetWorkflowCapabilityBindingEventV1(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000002401")!,
            workspaceID: WorkspaceID(),
            assetID: UUID(uuidString: "00000000-0000-0000-0000-000000002402")!,
            kindBindingEventID: UUID(uuidString: "00000000-0000-0000-0000-000000002403")!,
            kindBindingRevision: 1,
            workflowPackageRelease: try PackageReleaseIdentityV1(
                packageID: "com.field-evidence.c39",
                schemaVersion: 1,
                contentVersion: 1
            ),
            capabilityIDs: [try AssetSemanticCapabilityIDV1("capability.inspect")],
            disposition: .ended,
            predecessorEventID: nil,
            revision: 1,
            mutationID: try MutationIDV1(rawValue: UUID()),
            recordedAt: Date(timeIntervalSince1970: 1_735_689_600),
            eventSHA256: String(repeating: "a", count: 64)
        )
        try event.validate()
        XCTAssertEqual(event.disposition, .ended)
    }

    private let fileManager = FileManager.default

    func testFinalizationWorkflowBranchesMatchNativeOutcomeAndEvidenceRules() throws {
        let prefix = "native.sign.finalization."
        let stages: [(WorkflowStage, [String], String)] = [
            (.check, ["no_visible_issue", "visible_issue", "could_not_verify"], "visible_issue"),
            (.recheck, ["resolved", "issue_still_visible", "original_resolved_different_issue", "could_not_verify"],
             "original_resolved_different_issue"),
        ]
        for (stage, outcomes, conditionOutcome) in stages {
            let graph = try ShippingIlluminatedSignAdapterV1.finalizationWorkflow(from: .illuminatedSignV1, stage: stage)
            for outcome in outcomes {
                for wide in [false, true] {
                    for close in [false, true] {
                        var facts: [String: WorkflowFactValueV1] = [
                            prefix + "after_dark": .option("accepted"),
                            prefix + "safe_authorized_position": .option("accepted"),
                            prefix + "wide_present": .option(wide ? "present" : "absent"),
                            prefix + "close_present": .option(close ? "present" : "absent"),
                            prefix + "outcome": .option(outcome),
                            prefix + "condition": .option("physical_damage"),
                            prefix + "could_not_verify_reason": .option("conditions_changed"),
                        ]
                        let isCNV = outcome == "could_not_verify"
                        let expected = isCNV ? "completed_could_not_verify" : (wide && close ? "completed" : "blocked")
                        let path = try traverseFinalization(graph, facts: facts)
                        XCTAssertEqual(path.terminal, expected, "\(stage) \(outcome) wide=\(wide) close=\(close)")
                        XCTAssertEqual(path.evidence, (wide ? ["wide_context"] : []) + (close ? ["close_detail"] : []))
                        XCTAssertNil(facts[prefix + "could_not_verify_note"], "The native optional CNV note must stay optional")
                        if outcome == conditionOutcome && wide && close {
                            facts.removeValue(forKey: prefix + "condition")
                            XCTAssertEqual(try traverseFinalization(graph, facts: facts).terminal, "blocked")
                            facts[prefix + "condition"] = .option("unknown_condition")
                            XCTAssertEqual(try traverseFinalization(graph, facts: facts).terminal, "blocked")
                        }
                    }
                }
            }
            let baseline: [String: WorkflowFactValueV1] = [
                prefix + "after_dark": .option("accepted"), prefix + "safe_authorized_position": .option("accepted"),
                prefix + "wide_present": .option("present"), prefix + "close_present": .option("present"),
                prefix + "outcome": .option("could_not_verify"),
                prefix + "could_not_verify_reason": .option("conditions_changed"),
            ]
            let invalidFacts: [WorkflowFactValueV1?] = [nil, .unknown, .option("not_a_valid_choice")]
            for field in ["after_dark", "safe_authorized_position", "wide_present", "close_present", "outcome", "could_not_verify_reason"] {
                for value in invalidFacts {
                    var hostile = baseline
                    hostile[prefix + field] = value
                    XCTAssertEqual(try traverseFinalization(graph, facts: hostile).terminal, "blocked", field)
                }
            }
            for reason in SignPack.illuminatedSignV1.couldNotVerifyReasons.entries {
                var facts = baseline
                facts[prefix + "could_not_verify_reason"] = .option(reason.key)
                XCTAssertEqual(try traverseFinalization(graph, facts: facts).terminal, "completed_could_not_verify")
            }
        }
        XCTAssertThrowsError(try ShippingIlluminatedSignAdapterV1.finalizationWorkflow(from: .illuminatedSignV1, stage: .work))
    }

    private func traverseFinalization(_ graph: WorkflowDefinitionV1, facts: [String: WorkflowFactValueV1]) throws
        -> (terminal: String, evidence: [String]) {
        var nodeID = graph.entryNodeID
        var visited = Set<String>()
        var evidence: [String] = []
        while visited.count < graph.nodes.count {
            guard visited.insert(nodeID).inserted else { throw InspectionKernelFailureV1.cycleDetected }
            let node = try XCTUnwrap(graph.nodes.first { $0.nodeID == nodeID })
            if node.kind == .terminal { return (nodeID, evidence) }
            if node.kind == .branch {
                nodeID = try XCTUnwrap(node.branchDestinations).destination(
                    for: XCTUnwrap(node.predicate).evaluate(facts: facts))
            } else {
                guard node.kind != .repeatGroup, node.outgoingNodeIDs.count == 1 else {
                    throw InspectionKernelFailureV1.invalidValue
                }
                if let purpose = node.evidencePurposeID { evidence.append(purpose) }
                nodeID = try XCTUnwrap(node.outgoingNodeIDs.first)
            }
        }
        throw InspectionKernelFailureV1.limitExceeded
    }

    @MainActor
    func testRealCheckCompletionsBindKnownAndPartialEvidenceOutcomes() async throws {
        let cases: [(CheckOutcomeSelection, Int, String)] = [
            (.couldNotVerify(reasonKey: "conditions_changed", note: nil), 1, "could_not_verify"),
            (.couldNotVerify(reasonKey: "conditions_changed", note: nil), 2, "could_not_verify"),
            (.noVisibleIssue, 2, "no_visible_issue"),
            (.visibleIssue(labelKey: "physical_damage"), 2, "visible_issue"),
        ]
        for (selection, count, outcome) in cases {
            let fixture = try await makeShippingCompletion("check-\(outcome)-\(count)", selection: selection, evidenceCount: count)
            defer { fixture.harness.cleanup(fileManager: fileManager) }
            XCTAssertEqual(fixture.record.outcomeKey, outcome)
            let snapshot = try ReportSnapshotEncoderV1().decode(Data(contentsOf:
                fixture.harness.session.generationRootURL.appendingPathComponent(fixture.report.snapshotRelativePath)))
            XCTAssertEqual(snapshot.evidence.filter { $0.recordID == fixture.record.id }.count, count)
            let reference = try XCTUnwrap(fixture.finalizer.completedInspectionReference(recordID: fixture.record.id,
                expectedAssetID: fixture.asset.id, expectedRelease: fixture.release))
            XCTAssertEqual(reference.completionSHA256, fixture.report.snapshotSHA256)
            let paired = try XCTUnwrap(fixture.harness.dependencies.writer.finalizationEvidence(recordID: fixture.record.id))
            XCTAssertEqual(reference.revision, try paired.workflowRecordRevision(recordID: fixture.record.id))
        }
    }

    @MainActor
    func testRealRecheckCompletionsRetainEveryNativeOutcomeAndOriginalHistory() async throws {
        let cases: [(CheckOutcomeSelection, Int, String)] = [
            (.resolved(note: nil), 2, "resolved"), (.issueStillVisible(note: nil), 2, "issue_still_visible"),
            (.originalResolvedDifferentIssue(labelKey: "physical_damage", note: nil), 2, "original_resolved_different_issue"),
            (.couldNotVerify(reasonKey: "conditions_changed", note: nil), 0, "could_not_verify"),
            (.couldNotVerify(reasonKey: "conditions_changed", note: nil), 1, "could_not_verify"),
            (.couldNotVerify(reasonKey: "conditions_changed", note: nil), 2, "could_not_verify"),
        ]
        for (selection, count, outcome) in cases {
            let support = fileManager.temporaryDirectory.appendingPathComponent("completion-recheck-\(UUID().uuidString)", isDirectory: true)
            let fixture = try await WorkCanonicalCurrentRouteFixtureV1.make(applicationSupportURL: support,
                pack: .illuminatedSignV1, workPhotoData: nil)
            defer { try? fixture.close(); try? fileManager.removeItem(at: support) }
            let runner = try CheckRunnerCoordinator(modelContext: fixture.context,
                packageLifecycleDependencies: fixture.lifecycleDependencies, packageLifecycleProfile: fixture.lifecycleProfile)
            try runner.requestRecheck(assetID: fixture.assetID, issueID: fixture.issueID)
            let observed = fixture.workSubmission.completedAt.addingTimeInterval(60)
            _ = try runner.beginCheck(assetID: fixture.assetID, timeZoneID: "America/New_York", isTimeZoneConfirmed: true,
                afterDarkAccepted: true, safePositionAccepted: true, observedAt: observed)
            runner.configureCapture(generationRootURL: fixture.session.generationRootURL)
            for index in 0..<count {
                let candidate = try await runner.importCandidate(assetID: fixture.assetID,
                    sourceData: WorkCanonicalIntegrationTestSupportV1.makePNG(seed: UInt8(70 + index)),
                    createdAt: observed.addingTimeInterval(TimeInterval(index + 1)))
                _ = try await runner.accept(candidate: candidate, assetID: fixture.assetID)
            }
            let result = try await runner.finalize(assetID: fixture.assetID, selection: selection,
                completedAt: observed.addingTimeInterval(10), snapshotCreatedAt: observed.addingTimeInterval(11),
                sourceApp: .init(build: "completion-recheck", version: "1.0"))
            let finalizer = try FinalizationService(modelContext: fixture.context, signPack: .illuminatedSignV1,
                generationRootURL: fixture.session.generationRootURL, workspaceWriter: fixture.lifecycleDependencies.writer)
            let release = try publishedShippingRelease(stage: .recheck)
            let reference = try XCTUnwrap(finalizer.completedInspectionReference(recordID: result.recordID,
                expectedAssetID: fixture.assetID, expectedRelease: release))
            XCTAssertEqual(reference.completionSHA256, result.snapshotSHA256)
            let snapshot = try ReportSnapshotEncoderV1().decode(Data(contentsOf:
                fixture.session.generationRootURL.appendingPathComponent(result.snapshotRelativePath)))
            XCTAssertEqual(snapshot.stage, "recheck")
            XCTAssertEqual(snapshot.outcome, outcome)
            XCTAssertEqual(snapshot.history.map(\.recordID), [fixture.openingRecordID, fixture.workRecordID])
            XCTAssertEqual(snapshot.evidence.filter { $0.recordID == result.recordID }.count, count)
            let paired = try XCTUnwrap(fixture.lifecycleDependencies.writer.finalizationEvidence(recordID: result.recordID))
            guard case let .finalizeCheck(command) = paired.envelope.command else { return XCTFail("Recheck must use actual finalization receipt") }
            XCTAssertEqual(command.writerAuthority?.sourceBinding.inspectionRelease?.workflowSHA256, release.workflowSHA256)
            XCTAssertThrowsError(try finalizer.completedInspectionReference(recordID: result.recordID,
                expectedAssetID: fixture.assetID, expectedRelease: publishedShippingRelease(stage: .check)))
        }
    }

    @MainActor
    func testFinalizedInspectionCompletionKeepsOriginalReceiptAcrossPDFStatesAndCorrections() async throws {
        let fixture = try await makeShippingCompletion("completion-corrections")
        let harness = fixture.harness
        defer { harness.cleanup(fileManager: fileManager) }
        let writer = harness.dependencies.writer
        let original = try XCTUnwrap(fixture.finalizer.completedInspectionReference(
            recordID: fixture.record.id, expectedAssetID: fixture.asset.id, expectedRelease: fixture.release))
        let evidence = try XCTUnwrap(writer.finalizationEvidence(recordID: fixture.record.id))
        let mutationID = try MutationIDV1(rawValue: XCTUnwrap(fixture.record.finalizationMutationID))
        XCTAssertEqual(try writer.finalizationEvidence(mutationID: mutationID), evidence)
        XCTAssertEqual(original.revision, try evidence.workflowRecordRevision(recordID: fixture.record.id))
        XCTAssertEqual(original.completionSHA256, fixture.report.snapshotSHA256)
        guard case let .finalizeCheck(command) = evidence.envelope.command else {
            return XCTFail("Shipping inspection must retain its actual finalize-check receipt")
        }
        let binding = try XCTUnwrap(command.writerAuthority?.sourceBinding.inspectionRelease)
        XCTAssertEqual(binding, try ShippingIlluminatedSignAdapterV1.finalizationInspectionRelease(
            from: .illuminatedSignV1, stage: .check))
        XCTAssertEqual(binding.packageReleaseID, fixture.release.packageReleaseID)
        XCTAssertEqual(fixture.report.pdfState, ReportPDFState.pending.rawValue)

        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let failingRenderer = try ReportRenderService(modelContext: harness.session.modelContext,
            lifecycleDependencies: harness.dependencies, lifecycleProfile: profile,
            failureInjection: .init(failOnceAt: .render))
        XCTAssertEqual(try failingRenderer.attemptPendingReport(id: fixture.report.id), .failed(reportID: fixture.report.id))
        XCTAssertEqual(fixture.report.pdfState, ReportPDFState.failed.rawValue)
        XCTAssertEqual(try fixture.finalizer.completedInspectionReference(recordID: fixture.record.id,
            expectedAssetID: fixture.asset.id, expectedRelease: fixture.release), original)
        let retry = try ReportRenderService.transitionMutation(report: fixture.report,
            writer: writer, transition: .failedToPending)
        _ = try writer.commitReportPDFTransition(retry)
        let renderer = try ReportRenderService(modelContext: harness.session.modelContext,
            lifecycleDependencies: harness.dependencies, lifecycleProfile: profile)
        _ = try renderer.renderPendingReport(id: fixture.report.id)
        let delivery = try ReportDeliveryCoordinator(modelContext: harness.session.modelContext,
            lifecycleDependencies: harness.dependencies, lifecycleProfile: profile)
        var record = fixture.record
        var report = fixture.report
        var preserved: [(recordID: UUID, reference: RoundItemCompletionReferenceV1,
                         snapshotURL: URL, snapshot: Data, pdfURL: URL, pdf: Data)] = []
        for iteration in 0...2 {
            let completion = try XCTUnwrap(fixture.finalizer.completedInspectionReference(recordID: record.id,
                expectedAssetID: fixture.asset.id, expectedRelease: fixture.release))
            let snapshotURL = harness.session.generationRootURL.appendingPathComponent(report.snapshotRelativePath)
            let pdfURL = harness.session.generationRootURL.appendingPathComponent(try XCTUnwrap(report.pdfRelativePath))
            preserved.append((record.id, completion, snapshotURL, try Data(contentsOf: snapshotURL),
                              pdfURL, try Data(contentsOf: pdfURL)))
            for prior in preserved {
                XCTAssertEqual(try fixture.finalizer.completedInspectionReference(recordID: prior.recordID,
                    expectedAssetID: fixture.asset.id, expectedRelease: fixture.release), prior.reference)
                XCTAssertEqual(try Data(contentsOf: prior.snapshotURL), prior.snapshot)
                XCTAssertEqual(try Data(contentsOf: prior.pdfURL), prior.pdf)
            }
            guard iteration < 2 else { break }
            let validated = try delivery.validatedReadyReport(id: report.id)
            let packet = try XCTUnwrap(harness.session.modelContext.fetch(FetchDescriptor<Packet>())
                .first { $0.id == report.packetID })
            let corrected = try await fixture.finalizer.finalizeCorrection(.init(currentRecord: record,
                packet: packet, currentReport: report, currentSnapshot: validated.snapshot,
                note: "Clerical correction \(iteration + 1)",
                snapshotCreatedAt: validated.snapshot.snapshotCreatedAt.addingTimeInterval(10),
                sourceApp: .init(build: "completion-\(iteration + 1)", version: "1.0"),
                identifiers: .init(mutationID: UUID(), recordID: UUID(), reportID: UUID())))
            record = try XCTUnwrap(harness.session.modelContext.fetch(FetchDescriptor<WorkflowRecord>())
                .first { $0.id == corrected.recordID })
            report = try XCTUnwrap(harness.session.modelContext.fetch(FetchDescriptor<Report>())
                .first { $0.id == corrected.reportID })
            XCTAssertEqual(report.pdfState, ReportPDFState.pending.rawValue)
            let correctedEvidence = try XCTUnwrap(writer.finalizationEvidence(recordID: record.id))
            guard case let .finalizeCorrection(correction) = correctedEvidence.envelope.command else {
                return XCTFail("Correction must use its original paired receipt")
            }
            XCTAssertEqual(correction.writerAuthority?.sourceBinding.inspectionRelease, binding)
            XCTAssertNotNil(try fixture.finalizer.completedInspectionReference(recordID: record.id,
                expectedAssetID: fixture.asset.id, expectedRelease: fixture.release))
            XCTAssertEqual(try fixture.finalizer.completedInspectionReference(recordID: fixture.record.id,
                expectedAssetID: fixture.asset.id, expectedRelease: fixture.release), original)
            _ = try renderer.renderPendingReport(id: report.id)
        }
        XCTAssertEqual(preserved.count, 3)
        let requests = preserved.reversed().map {
            FinalizationService.CompletedInspectionRequest(recordID: $0.recordID,
                expectedAssetID: fixture.asset.id, expectedRelease: fixture.release)
        }
        let ordered = try fixture.finalizer.completedInspectionReferences(requests: requests)
        let expected: [RoundItemCompletionReferenceV1?] = preserved.reversed().map { $0.reference }
        XCTAssertEqual(ordered, expected, "Every correction retains its own original paired receipt")
        XCTAssertEqual(try harness.session.modelContext.fetchCount(FetchDescriptor<Report>()), 3)
        XCTAssertEqual(try harness.session.modelContext.fetchCount(FetchDescriptor<Packet>()), 1)
    }

    @MainActor
    func testCompletedInspectionBatchPreservesOrderBoundsAndRejectsAnyInvalidSelection() async throws {
        let fixture = try await makeShippingCompletion("completion-batch")
        defer { fixture.harness.cleanup(fileManager: fileManager) }
        let finalizer = fixture.finalizer
        let writer = fixture.harness.dependencies.writer
        let revision = try writer.currentRevision()
        let request = FinalizationService.CompletedInspectionRequest(recordID: fixture.record.id,
            expectedAssetID: fixture.asset.id, expectedRelease: fixture.release)
        let missing = FinalizationService.CompletedInspectionRequest(recordID: UUID(),
            expectedAssetID: fixture.asset.id, expectedRelease: fixture.release)
        let reference = try XCTUnwrap(finalizer.completedInspectionReference(recordID: fixture.record.id,
            expectedAssetID: fixture.asset.id, expectedRelease: fixture.release))
        let expected: [RoundItemCompletionReferenceV1?] = [reference, nil, reference]
        XCTAssertEqual(try finalizer.completedInspectionReferences(requests: [request, missing, request]), expected)
        XCTAssertEqual(try finalizer.completedInspectionReferences(requests: Array(repeating: missing, count: 512)),
            [RoundItemCompletionReferenceV1?](repeating: nil, count: 512))
        XCTAssertThrowsError(try finalizer.completedInspectionReferences(requests: Array(repeating: missing, count: 513)))
        let wrongAsset = FinalizationService.CompletedInspectionRequest(recordID: fixture.record.id,
            expectedAssetID: UUID(), expectedRelease: fixture.release)
        let wrongWorkflow = FinalizationService.CompletedInspectionRequest(recordID: fixture.record.id,
            expectedAssetID: fixture.asset.id, expectedRelease: try publishedShippingRelease(stage: .recheck))
        XCTAssertThrowsError(try finalizer.completedInspectionReferences(requests: [request, missing, wrongAsset]))
        XCTAssertThrowsError(try finalizer.completedInspectionReferences(requests: [request, wrongWorkflow]))

        let validator = try SnapshotValidatorV1(modelContext: fixture.harness.session.modelContext,
            generationRootURL: fixture.harness.session.generationRootURL, signPack: .illuminatedSignV1)
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: fixture.harness.session.generationRootURL)
        var consumed: [UUID] = []
        XCTAssertThrowsError(try validator.validateCompletedInspectionReports(
            Array(repeating: fixture.report, count: 513), expectedRootIdentity: rootIdentity) { report, _ in
                consumed.append(report.id)
            })
        XCTAssertTrue(consumed.isEmpty, "Raw report count is checked before any selected content is consumed")
        try validator.validateCompletedInspectionReports([fixture.report, fixture.report], expectedRootIdentity: rootIdentity) { report, value in
            XCTAssertEqual(value.snapshotSHA256, reference.completionSHA256)
            consumed.append(report.id)
        }
        XCTAssertEqual(consumed, [fixture.report.id, fixture.report.id])

        let snapshotURL = fixture.harness.session.generationRootURL.appendingPathComponent(fixture.report.snapshotRelativePath)
        let originalBytes = try Data(contentsOf: snapshotURL)
        try Data("altered selected snapshot".utf8).write(to: snapshotURL)
        XCTAssertThrowsError(try finalizer.completedInspectionReferences(requests: [missing, request]))
        try originalBytes.write(to: snapshotURL)
        XCTAssertEqual(try finalizer.completedInspectionReferences(requests: [request, missing, request]), expected)
        XCTAssertEqual(try Data(contentsOf: snapshotURL), originalBytes)
        XCTAssertEqual(try writer.currentRevision(), revision)
        writer.invalidate()
        XCTAssertThrowsError(try finalizer.completedInspectionReferences(requests: [missing, request])) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .writerInvalidated)
        }
    }

    @MainActor
    func testProductionMyDayAcceptsActualInspectionCompletionAndRejectsChangedSnapshot() async throws {
        let fixture = try await makeShippingCompletion("completion-my-day")
        let harness = fixture.harness
        defer { harness.cleanup(fileManager: fileManager) }
        let writer = harness.dependencies.writer
        let workspaceID = harness.session.workspaceID
        let completedAt = try XCTUnwrap(fixture.record.completedAt)
        let completion = try XCTUnwrap(fixture.finalizer.completedInspectionReference(recordID: fixture.record.id,
            expectedAssetID: fixture.asset.id, expectedRelease: fixture.release))
        // The publication owner produced these exact package/workflow bytes.
        // Persist its canonical test input; this does not qualify UI promotion.
        let promoted = try PromotedPackageReleaseV1(releaseRecordID: UUID(), workspaceID: workspaceID,
            packageRelease: fixture.release, mutationID: writer.makeMutationID(), promotedAt: completedAt)
        harness.session.modelContext.insert(try PromotedPackageReleaseRow(promoted))
        try harness.session.modelContext.save()
        let localActor = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspaceID,
            displayName: "Round inspector")
        let recorder = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: workspaceID, actor: localActor,
            responsibility: .recordedBy, displayNameAtTime: localActor.displayName, capturedAt: completedAt)
        _ = try writer.execute(.applyPartyAccountability(.appendActorSnapshot(recorder)),
            mutationID: writer.makeMutationID())
        let item = try RoundItemV1(itemID: UUID(), order: 0,
            selection: .init(assetID: fixture.asset.id, siteID: fixture.asset.siteID,
                labelAtSelection: fixture.asset.label),
            requirement: .init(packageRelease: .init(fixture.release), requiredContent: []))
        var round = try RoundSessionV1(workspaceID: workspaceID, sessionID: UUID(), predecessor: nil,
            revision: 1, mutationID: writer.makeMutationID(), state: .draft, transition: .create,
            items: [item], recordedBy: recorder, recordedAt: completedAt)
        _ = try writer.commitRoundSession(.init(workspaceID: workspaceID, expectedRevision: 0,
            mutationID: round.mutationID, session: round))
        for (index, transition) in [RoundSessionTransitionV1.start, .visitItem, .completeItem].enumerated() {
            let visit = try RoundItemVisitV1(visitedAt: completedAt, recordedBy: recorder)
            let successorItem = try RoundItemV1(itemID: item.itemID, order: item.order, selection: item.selection,
                requirement: item.requirement, disposition: index == 0 ? .pending : (index == 1 ? .visited : .completed),
                visit: index == 0 ? nil : visit, completion: index == 2 ? completion : nil)
            let successor = try RoundSessionV1(workspaceID: workspaceID, sessionID: round.sessionID,
                predecessor: round, revision: round.revision + 1, mutationID: writer.makeMutationID(),
                state: .active, transition: transition, transitionItemID: index == 0 ? nil : item.itemID,
                items: [successorItem], recordedBy: recorder,
                recordedAt: completedAt.addingTimeInterval(TimeInterval(index + 1)))
            _ = try writer.commitRoundSession(.init(workspaceID: workspaceID, expectedRevision: round.revision,
                mutationID: successor.mutationID, session: successor))
            round = successor
        }
        try await harness.coordinator.awaitSearchIndexLifecycle()
        let authentication = CompletionReadAuthentication()
        let gate = AppAccessGateV1(setting: .absentDisabled, authentication: authentication,
            clock: SystemApplicationClock(), identifiers: SystemApplicationIDSource())
        let ledger = try OwnedStorageLedgerV1(applicationSupportURL: harness.root, capacityProvider: { _ in 1_000_000_000 })
        let provider = harness.coordinator.makeMyDaySourceProvider(accessGate: gate, ownedStorageLedger: ledger)
        let revision = try writer.currentRevision()
        let receipts = try harness.session.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>())
        let storage = ledger.snapshot()
        let snapshotURL = harness.session.generationRootURL.appendingPathComponent(fixture.report.snapshotRelativePath)
        let bytes = try Data(contentsOf: snapshotURL)
        let evaluatedAt = completedAt.addingTimeInterval(100)
        let assessed = try await provider.snapshot(evaluatedAt: evaluatedAt)
        let reference = MyDayEligibleReferenceV1.roundSession(workspaceID: workspaceID,
            sessionID: round.sessionID, revision: round.revision, sessionSHA256: round.sessionSHA256)
        guard case let .roundManifest(manifest)? = assessed.readinessAssessments.first(where: { $0.reference == reference })?.assessment else {
            return XCTFail("Actual matching completed inspection must reach production readiness")
        }
        try manifest.validate()
        XCTAssertEqual(manifest.session, try round.reference)
        XCTAssertEqual(manifest.status, .ready)
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try harness.session.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), receipts)
        XCTAssertEqual(ledger.snapshot(), storage)
        #if DEBUG
        provider.afterSourceMaterializationForTesting = { await gate.markConfigurationUnknown() }
        do { _ = try await provider.snapshot(evaluatedAt: evaluatedAt); XCTFail("Locked completed-inspection read published") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        provider.afterSourceMaterializationForTesting = nil
        await gate.eraseAccessState()
        #endif
        try Data("changed after finalization".utf8).write(to: snapshotURL)
        do { _ = try await provider.snapshot(evaluatedAt: evaluatedAt); XCTFail("Changed snapshot supplied Round readiness") }
        catch { XCTAssertFalse(error is CancellationError) }
        try bytes.write(to: snapshotURL)
        let restored = try await provider.snapshot(evaluatedAt: evaluatedAt)
        guard case .roundManifest? = restored.readinessAssessments.first(where: { $0.reference == reference })?.assessment else {
            return XCTFail("Restored immutable bytes must remain readable")
        }
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try harness.session.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), receipts)
        // A later unavailable package must not prevent validation of the
        // earlier supported completion's actual immutable snapshot.
        let secondAssetMutation = try writer.makeMutationID()
        _ = try writer.execute(try makeFirstAssetCommand(label: "completion-unavailable-neighbor",
            mutationID: secondAssetMutation), mutationID: secondAssetMutation)
        let secondAsset = try XCTUnwrap(harness.session.modelContext.fetch(FetchDescriptor<Asset>())
            .first { $0.id != fixture.asset.id })
        let secondRunner = try CheckRunnerCoordinator(modelContext: harness.session.modelContext,
            packageLifecycleDependencies: harness.dependencies,
            packageLifecycleProfile: WorkspacePackageLifecycleCompatibilityV1.shippingProfile())
        secondRunner.configureCapture(generationRootURL: harness.session.generationRootURL)
        _ = try secondRunner.beginCheck(assetID: secondAsset.id, timeZoneID: "America/New_York", isTimeZoneConfirmed: true,
            afterDarkAccepted: true, safePositionAccepted: true, observedAt: completedAt.addingTimeInterval(10))
        let secondResult = try await secondRunner.finalize(assetID: secondAsset.id,
            selection: .couldNotVerify(reasonKey: "conditions_changed", note: nil),
            completedAt: completedAt.addingTimeInterval(20), snapshotCreatedAt: completedAt.addingTimeInterval(21),
            sourceApp: .init(build: "completion-unavailable", version: "1.0"))
        let secondCompletion = try XCTUnwrap(fixture.finalizer.completedInspectionReference(recordID: secondResult.recordID,
            expectedAssetID: secondAsset.id, expectedRelease: fixture.release))
        XCTAssertNotEqual(secondCompletion.completionID, completion.completionID)
        let unavailableRelease = try publishedShippingRelease(stage: .recheck)
        let secondItem = try RoundItemV1(itemID: UUID(), order: 1,
            selection: .init(assetID: secondAsset.id, siteID: secondAsset.siteID, labelAtSelection: secondAsset.label),
            requirement: .init(packageRelease: .init(unavailableRelease), requiredContent: []))
        let mixedRecordedAt = completedAt.addingTimeInterval(30)
        var mixed = try RoundSessionV1(workspaceID: workspaceID, sessionID: UUID(), predecessor: nil,
            revision: 1, mutationID: writer.makeMutationID(), state: .draft, transition: .create,
            items: [item, secondItem], recordedBy: recorder, recordedAt: mixedRecordedAt)
        _ = try writer.commitRoundSession(.init(workspaceID: workspaceID, expectedRevision: 0,
            mutationID: mixed.mutationID, session: mixed))
        let started = try RoundSessionV1(workspaceID: workspaceID, sessionID: mixed.sessionID, predecessor: mixed,
            revision: mixed.revision + 1, mutationID: writer.makeMutationID(), state: .active, transition: .start,
            items: mixed.items, recordedBy: recorder, recordedAt: mixedRecordedAt)
        _ = try writer.commitRoundSession(.init(workspaceID: workspaceID, expectedRevision: mixed.revision,
            mutationID: started.mutationID, session: started))
        mixed = started
        for index in 0..<2 {
            for disposition in [RoundItemDispositionV1.visited, .completed] {
                var items = mixed.items
                let selected = items[index]
                items[index] = try .init(itemID: selected.itemID, order: selected.order, selection: selected.selection,
                    requirement: selected.requirement, disposition: disposition,
                    visit: .init(visitedAt: mixedRecordedAt, recordedBy: recorder),
                    completion: disposition == .completed ? (index == 0 ? completion : secondCompletion) : nil)
                let next = try RoundSessionV1(workspaceID: workspaceID, sessionID: mixed.sessionID, predecessor: mixed,
                    revision: mixed.revision + 1, mutationID: writer.makeMutationID(), state: .active,
                    transition: disposition == .visited ? .visitItem : .completeItem,
                    transitionItemID: selected.itemID, items: items, recordedBy: recorder, recordedAt: mixedRecordedAt)
                _ = try writer.commitRoundSession(.init(workspaceID: workspaceID, expectedRevision: mixed.revision,
                    mutationID: next.mutationID, session: next))
                mixed = next
            }
        }
        try await harness.coordinator.awaitSearchIndexLifecycle()
        let authority = ProductionOfflineReadinessAuthorityV1(session: harness.coordinator, accessGate: gate,
            clock: SystemApplicationClock(), ownedStorageLedger: ledger, expectedApplicationSupportURL: harness.root)
        let mixedReference = MyDayEligibleReferenceV1.roundSession(workspaceID: workspaceID,
            sessionID: mixed.sessionID, revision: mixed.revision, sessionSHA256: mixed.sessionSHA256)
        let missingPackage = try await authority.assess(mixedReference)
        XCTAssertEqual(missingPackage.assessment, .unavailable(.completionAuthorityUnavailable))
        let mixedRevision = try writer.currentRevision()
        try Data("corrupt supported completion beside unavailable package".utf8).write(to: snapshotURL)
        do { _ = try await authority.assess(mixedReference); XCTFail("Unavailable package hid a corrupt supported completion") }
        catch { XCTAssertFalse(error is CancellationError) }
        try bytes.write(to: snapshotURL)
        let restoredMixed = try await authority.assess(mixedReference)
        XCTAssertEqual(restoredMixed.assessment, .unavailable(.completionAuthorityUnavailable))
        XCTAssertEqual(try writer.currentRevision(), mixedRevision)
        let authenticationCount = await authentication.count
        XCTAssertEqual(authenticationCount, 0)
    }

    @MainActor
    func testFinalizedInspectionCompletionRejectsWrongSelectionTamperingAndRetiredWriter() async throws {
        let fixture = try await makeShippingCompletion("completion-rejection")
        let harness = fixture.harness
        defer { harness.cleanup(fileManager: fileManager) }
        let original = try XCTUnwrap(fixture.finalizer.completedInspectionReference(recordID: fixture.record.id,
            expectedAssetID: fixture.asset.id, expectedRelease: fixture.release))
        XCTAssertNil(try fixture.finalizer.completedInspectionReference(recordID: UUID(),
            expectedAssetID: fixture.asset.id, expectedRelease: fixture.release))
        XCTAssertThrowsError(try fixture.finalizer.completedInspectionReference(recordID: fixture.record.id,
            expectedAssetID: UUID(), expectedRelease: fixture.release))
        let wrongWorkflow = try publishedShippingRelease(stage: .recheck)
        XCTAssertNotEqual(wrongWorkflow.workflowSHA256, fixture.release.workflowSHA256)
        XCTAssertThrowsError(try fixture.finalizer.completedInspectionReference(recordID: fixture.record.id,
            expectedAssetID: fixture.asset.id, expectedRelease: wrongWorkflow))
        let snapshotURL = harness.session.generationRootURL.appendingPathComponent(fixture.report.snapshotRelativePath)
        let bytes = try Data(contentsOf: snapshotURL)
        try Data("tampered snapshot".utf8).write(to: snapshotURL)
        XCTAssertThrowsError(try fixture.finalizer.completedInspectionReference(recordID: fixture.record.id,
            expectedAssetID: fixture.asset.id, expectedRelease: fixture.release))
        try bytes.write(to: snapshotURL)
        XCTAssertEqual(try fixture.finalizer.completedInspectionReference(recordID: fixture.record.id,
            expectedAssetID: fixture.asset.id, expectedRelease: fixture.release), original)
        let originalWriterID = try harness.dependencies.writer.currentRevision().writerInstanceID
        try harness.coordinator.invalidateAndReleaseWriter()
        XCTAssertThrowsError(try fixture.finalizer.completedInspectionReference(recordID: fixture.record.id,
            expectedAssetID: fixture.asset.id, expectedRelease: fixture.release)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .writerInvalidated)
        }
        let reopenedStore = try StoreGenerationFactory(applicationSupportURL: harness.root).openOrBootstrapCurrent()
        let reopened = try StoreSessionCoordinator(validatingSession: reopenedStore)
        defer { try? reopened.invalidateAndReleaseWriter() }
        XCTAssertNotEqual(try reopened.workspaceWriter.currentRevision().writerInstanceID, originalWriterID)
        let freshFinalizer = try FinalizationService(modelContext: reopened.modelContext, signPack: .illuminatedSignV1,
            generationRootURL: reopened.generationRootURL, workspaceWriter: reopened.workspaceWriter)
        XCTAssertEqual(try freshFinalizer.completedInspectionReference(recordID: fixture.record.id,
            expectedAssetID: fixture.asset.id, expectedRelease: fixture.release), original)
        XCTAssertEqual(try Data(contentsOf: snapshotURL), bytes)
    }

    private func publishedShippingRelease(stage: WorkflowStage) throws -> InspectionPackageReleaseV1 {
        let draft = try InspectionPackageReleaseV1.makeDraft(
            package: ShippingIlluminatedSignAdapterV1.inspectionPackage(),
            workflow: ShippingIlluminatedSignAdapterV1.finalizationWorkflow(from: .illuminatedSignV1, stage: stage))
        return try InspectionPackageReleasePublisherV1.publish(InspectionPackageReleasePublisherV1.test(draft)).release
    }

    @MainActor
    private func makeShippingCompletion(_ label: String,
        selection: CheckOutcomeSelection = .couldNotVerify(reasonKey: "conditions_changed", note: nil),
        evidenceCount: Int = 0) async throws
        -> (harness: Harness, asset: Asset, record: WorkflowRecord, report: Report,
            release: InspectionPackageReleaseV1, finalizer: FinalizationService) {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let harness = try makeHarness(label, profile: profile)
        do {
            let runner = try CheckRunnerCoordinator(modelContext: harness.session.modelContext,
                packageLifecycleDependencies: harness.dependencies, packageLifecycleProfile: profile)
            runner.configureCapture(generationRootURL: harness.session.generationRootURL)
            let mutationID = try harness.dependencies.writer.makeMutationID()
            _ = try harness.dependencies.writer.execute(try makeFirstAssetCommand(label: label,
                mutationID: mutationID), mutationID: mutationID)
            let asset = try XCTUnwrap(harness.session.modelContext.fetch(FetchDescriptor<Asset>()).first)
            _ = try runner.beginCheck(assetID: asset.id, timeZoneID: "America/New_York", isTimeZoneConfirmed: true,
                afterDarkAccepted: true, safePositionAccepted: true, observedAt: Date(timeIntervalSince1970: 1_768_800_000))
            for index in 0..<evidenceCount {
                let candidate = try await runner.importCandidate(assetID: asset.id,
                    sourceData: WorkCanonicalIntegrationTestSupportV1.makePNG(seed: UInt8(80 + index)),
                    createdAt: Date(timeIntervalSince1970: 1_768_800_001 + TimeInterval(index)))
                _ = try await runner.accept(candidate: candidate, assetID: asset.id)
            }
            let result = try await runner.finalize(assetID: asset.id,
                selection: selection,
                completedAt: Date(timeIntervalSince1970: 1_768_800_010),
                snapshotCreatedAt: Date(timeIntervalSince1970: 1_768_800_011),
                sourceApp: .init(build: "completion", version: "1.0"))
            let report = try XCTUnwrap(harness.session.modelContext.fetch(FetchDescriptor<Report>())
                .first { $0.id == result.reportID })
            let record = try XCTUnwrap(harness.session.modelContext.fetch(FetchDescriptor<WorkflowRecord>())
                .first { $0.id == report.sourceRecordID })
            let finalizer = try FinalizationService(modelContext: harness.session.modelContext, signPack: profile.package,
                generationRootURL: harness.session.generationRootURL, workspaceWriter: harness.dependencies.writer)
            return (harness, asset, record, report, try publishedShippingRelease(stage: .check), finalizer)
        } catch {
            harness.cleanup(fileManager: fileManager)
            throw error
        }
    }

    @MainActor
    func testV9_18G01ShippingLifecycleParityUsesOneClosedProfile() throws {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let package = SignPack.illuminatedSignV1

        XCTAssertEqual(profile.release, try PackageReleaseIdentityV1(package: package))
        XCTAssertEqual(profile.package, package)
        XCTAssertEqual(profile.stages.map(\.stageKey), ["check", "recheck", "work"])
        assertPackageOutcomeParity(profile: profile, package: package)
        XCTAssertEqual(
            profile.evidencePurposes.map(\.key),
            package.evidencePurposes.map(\.key)
        )
        XCTAssertEqual(
            profile.requiredAcknowledgementKeys,
            package.acknowledgements.map(\.key)
        )
        XCTAssertEqual(profile.pdfTemplate.id, "field.evidence.pdf.worklight.v1")
        XCTAssertEqual(profile.pdfTemplate.version, 1)
        XCTAssertEqual(
            WorkspacePackageLifecycleCompatibilityV1.expiration,
            PackFinalizationAdapterV1.expiresAfter
        )
    }

    @MainActor
    func testV9_18A01AlternatePackageFlowsThroughProductionDependencies() async throws {
        let package = try alternatePackage()
        let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(
            package: package
        )
        let harness = try makeHarness("alternate", profile: profile)
        defer { harness.cleanup(fileManager: fileManager) }

        let runner = try CheckRunnerCoordinator(
            modelContext: harness.session.modelContext,
            packageLifecycleDependencies: harness.dependencies,
            packageLifecycleProfile: profile
        )
        runner.configureCapture(generationRootURL: harness.session.generationRootURL)

        let placementMutationID = try harness.dependencies.writer.makeMutationID()
        _ = try harness.dependencies.writer.execute(
            try makeFirstAssetCommand(
                label: "Alternate",
                mutationID: placementMutationID,
                package: package
            ),
            mutationID: placementMutationID
        )
        let asset = try XCTUnwrap(
            harness.session.modelContext.fetch(FetchDescriptor<Asset>()).first
        )
        _ = try runner.beginCheck(
            assetID: asset.id,
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true,
            afterDarkAccepted: false,
            safePositionAccepted: true,
            observedAt: Date(timeIntervalSince1970: 1_768_800_000)
        )
        let finalized = try await runner.finalize(
            assetID: asset.id,
            selection: .couldNotVerify(reasonKey: "conditions_changed", note: nil),
            completedAt: Date(timeIntervalSince1970: 1_768_800_010),
            snapshotCreatedAt: Date(timeIntervalSince1970: 1_768_800_011),
            sourceApp: SourceAppSnapshotV1(build: "33", version: "1.0")
        )
        let record = try XCTUnwrap(
            harness.session.modelContext.fetch(FetchDescriptor<WorkflowRecord>()).first
        )
        let finalizationMutationID = try MutationIDV1(
            rawValue: XCTUnwrap(record.finalizationMutationID)
        )
        let finalizationReceipt = try XCTUnwrap(
            harness.dependencies.writer.durableReceipt(mutationID: finalizationMutationID)
        )
        let finalizationEnvelope = try XCTUnwrap(
            harness.dependencies.writer.finalizationEnvelope(mutationID: finalizationMutationID)
        )
        guard case let .finalizeCheck(finalizationCommand) = finalizationEnvelope.command else {
            return XCTFail("Alternate package finalization must use the canonical finalize-check command")
        }
        XCTAssertEqual(finalizationCommand.writerAuthority?.payload.workflowRecordAfter.packID,
                       profile.release.packageID)
        XCTAssertEqual(finalizationReceipt.mutationID, finalizationMutationID)
        XCTAssertNil(finalizationCommand.writerAuthority?.sourceBinding.inspectionRelease)
        let alternateFinalizer = try FinalizationService(modelContext: harness.session.modelContext,
            signPack: package, generationRootURL: harness.session.generationRootURL,
            workspaceWriter: harness.dependencies.writer)
        XCTAssertNil(try alternateFinalizer.completedInspectionReference(recordID: record.id,
            expectedAssetID: asset.id, expectedRelease: publishedShippingRelease(stage: .check)))

        let shippingProfile = try harness.dependencies.profileRegistry.resolve(
            PackageReleaseIdentityV1(package: .illuminatedSignV1)
        )
        let rendered = try ReportRenderService(
            modelContext: harness.session.modelContext,
            lifecycleDependencies: harness.dependencies,
            lifecycleProfile: shippingProfile
        ).renderPendingReport(id: finalized.reportID)
        let report = try XCTUnwrap(
            harness.session.modelContext.fetch(FetchDescriptor<Report>()).first
        )
        XCTAssertEqual(report.pdfState, ReportPDFState.ready.rawValue)
        XCTAssertEqual(report.pdfRelativePath, rendered.pdfRelativePath)
        XCTAssertEqual(report.pdfSHA256, rendered.pdfSHA256)
        let delivery = try ReportDeliveryCoordinator(
            modelContext: harness.session.modelContext,
            lifecycleDependencies: harness.dependencies,
            lifecycleProfile: shippingProfile
        ).loadReadyReport(id: finalized.reportID)
        XCTAssertEqual(delivery.reportID, finalized.reportID)
        XCTAssertEqual(delivery.pdfSHA256, rendered.pdfSHA256)
        let receiptRows = try harness.session.modelContext.fetch(
            FetchDescriptor<MutationReceiptRow>()
        )
        let pdfCommands: [ReportPDFTransitionMutationV1] = try receiptRows.compactMap { row -> ReportPDFTransitionMutationV1? in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
            guard case let .transitionReportPDF(command) = envelope.command else { return nil }
            return command
        }
        let pdfCommand = try XCTUnwrap(pdfCommands.first)
        let pdfReceipt = try XCTUnwrap(
            harness.dependencies.writer.reportPDFTransitionReceipt(for: pdfCommand)
        )

        XCTAssertEqual(profile.release.packageID, "test.field.evidence.alternate.v1")
        XCTAssertEqual(profile.package.nouns.asset.singular, "test fixture")
        XCTAssertEqual(profile.stages.map(\.stageKey), ["check", "recheck"])
        XCTAssertEqual(profile.stages.flatMap(\.outcomes).map(\.role).contains(.workRecorded), false)
        assertPackageOutcomeParity(profile: profile, package: package)
        XCTAssertEqual(
            profile.evidencePurposes.map(\.key),
            package.evidencePurposes.map(\.key)
        )
        XCTAssertEqual(
            try harness.dependencies.profileRegistry.resolve(profile.release),
            profile
        )
        let recoveryAdapter = try PackFinalizationRecoveryAdapterV1(
            dependencies: harness.dependencies,
            profile: profile,
            legacyModelContext: harness.session.modelContext
        )
        let recovery = try await recoveryAdapter.reconcile()
        XCTAssertEqual(recovery.packageRelease, profile.release)
        XCTAssertTrue(recovery.summary.recoveredDraftRecordIDs.isEmpty)
        XCTAssertTrue(recovery.zeroFeatureWriteClosureClaimed)

        let originalWriterInstanceID = try harness.dependencies.writer.currentRevision().writerInstanceID
        try harness.coordinator.invalidateAndReleaseWriter()
        let alternateOnlyRegistry = try WorkspacePackageLifecycleProfileRegistryV1(
            profiles: [profile]
        )
        var commerceWriterInstanceID: UUID?
        let startup = StartupRouter(
            applicationSupportURL: harness.root,
            lifecycleProfileRegistry: alternateOnlyRegistry,
            beforeCommerceActivation: { commerceWriterInstanceID = $0 }
        )
        defer { startup.failClosedPDFRecovery() }
        await startup.retryChecks()
        guard case let .ready(reopenedCoordinator, _, startupReportRecovery) = startup.route else {
            return XCTFail("Alternate-only startup must recover the existing package to ready")
        }
        XCTAssertTrue(startupReportRecovery.failedReportIDs.isEmpty)
        XCTAssertFalse(startup.hasPendingWriterCleanup)
        XCTAssertNil(startup.lastWriterCleanupFailure)
        XCTAssertEqual(reopenedCoordinator.lifecycleProfileRegistry, alternateOnlyRegistry)
        let reopenedDependencies = try reopenedCoordinator.packageLifecycleDependencies()
        let reopenedWriterInstanceID = try reopenedDependencies.writer.currentRevision().writerInstanceID
        XCTAssertEqual(commerceWriterInstanceID, reopenedWriterInstanceID)
        XCTAssertNotEqual(
            reopenedWriterInstanceID,
            originalWriterInstanceID
        )
        XCTAssertEqual(
            try reopenedDependencies.writer.durableReceipt(mutationID: finalizationMutationID),
            finalizationReceipt
        )
        XCTAssertEqual(
            try reopenedDependencies.writer.reportPDFTransitionReceipt(for: pdfCommand),
            pdfReceipt
        )
        let reopenedReport = try XCTUnwrap(
            reopenedCoordinator.modelContext.fetch(FetchDescriptor<Report>()).first
        )
        XCTAssertEqual(reopenedReport.pdfState, ReportPDFState.ready.rawValue)
        XCTAssertEqual(reopenedReport.pdfSHA256, rendered.pdfSHA256)
        XCTAssertEqual(
            try Data(
                contentsOf: reopenedCoordinator.generationRootURL.appendingPathComponent(
                    XCTUnwrap(reopenedReport.pdfRelativePath)
                )
            ),
            delivery.pdfData
        )
        withExtendedLifetime(runner) {}
    }

    @MainActor
    func testV9_18H01HardcodedReleaseAndForeignDependencyFailClosed() throws {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let first = try makeHarness("hostile-first", profile: profile)
        let second = try makeHarness("hostile-second", profile: profile)
        defer {
            first.cleanup(fileManager: fileManager)
            second.cleanup(fileManager: fileManager)
        }

        let unknownRelease = try PackageReleaseIdentityV1(
            packageID: "field.evidence.hardcoded.unknown",
            schemaVersion: 1,
            contentVersion: 1
        )
        XCTAssertThrowsError(
            try first.dependencies.profileRegistry.resolve(unknownRelease)
        )

        let foreignRequest = try WorkspacePackageLifecycleQueryRequestV1(
            workspaceID: second.dependencies.workspaceID,
            generationID: second.dependencies.generationID,
            operation: .query,
            identities: []
        )
        XCTAssertThrowsError(try first.dependencies.queryClient.query(foreignRequest)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongWorkspace)
        }

        let wrongGenerationRequest = try WorkspacePackageLifecycleQueryRequestV1(
            workspaceID: first.dependencies.workspaceID,
            generationID: second.dependencies.generationID,
            operation: .query,
            identities: []
        )
        XCTAssertThrowsError(try first.dependencies.queryClient.query(wrongGenerationRequest)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongGeneration)
        }
    }

    @MainActor
    func testV9_18I01CancellationAndCompetingMutationDoNotCreatePartialAuthority() async throws {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let harness = try makeHarness("interruption", profile: profile)
        defer { harness.cleanup(fileManager: fileManager) }

        let recovery = try PackFinalizationRecoveryAdapterV1(
            dependencies: harness.dependencies,
            profile: profile,
            legacyModelContext: harness.session.modelContext
        )
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await recovery.reconcile()
        }
        do {
            _ = try await cancelled.value
            XCTFail("A cancelled recovery must fail before discovering or applying authority")
        } catch is CancellationError {
            // Expected fail-closed interruption boundary.
        }

        let firstMutationID = try harness.dependencies.writer.makeMutationID()
        let firstCommand = try makeFirstAssetCommand(
            label: "Primary",
            mutationID: firstMutationID
        )
        let firstOutcome = try harness.dependencies.writer.execute(
            firstCommand,
            mutationID: firstMutationID
        )
        let competingCommand = try makeFirstAssetCommand(
            label: "Competing",
            mutationID: firstOutcome.mutationID
        )
        let competingRequest = try request(
            mutationID: firstOutcome.mutationID,
            command: competingCommand,
            writer: harness.dependencies.writer
        )
        XCTAssertThrowsError(try harness.dependencies.writer.execute(competingRequest)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(try harness.dependencies.writer.currentRevision().revision, 1)
    }

    @MainActor
    func testV9_18R01TwoWorkspacesRemainIsolatedAndRecoverIndependently() async throws {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let first = try makeHarness("recovery-first", profile: profile)
        let second = try makeHarness("recovery-second", profile: profile)
        defer {
            first.cleanup(fileManager: fileManager)
            second.cleanup(fileManager: fileManager)
        }
        XCTAssertNotEqual(first.dependencies.workspaceID, second.dependencies.workspaceID)
        XCTAssertNotEqual(first.dependencies.generationID, second.dependencies.generationID)

        let firstMutationID = try first.dependencies.writer.makeMutationID()
        _ = try first.dependencies.writer.execute(
            try makeFirstAssetCommand(
                label: "First only",
                mutationID: firstMutationID
            ),
            mutationID: firstMutationID
        )
        let firstAsset = try XCTUnwrap(
            try first.session.modelContext.fetch(FetchDescriptor<Asset>()).first
        )
        let identity = try WorkspaceEntityIdentityV1(kind: .asset, id: firstAsset.id)
        let localRequest = try WorkspacePackageLifecycleQueryRequestV1(
            workspaceID: first.dependencies.workspaceID,
            generationID: first.dependencies.generationID,
            operation: .query,
            identities: [identity]
        )
        XCTAssertEqual(
            try first.dependencies.queryClient.query(localRequest).existingIdentities,
            [identity]
        )
        XCTAssertThrowsError(try second.dependencies.queryClient.query(localRequest)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongWorkspace)
        }
        XCTAssertTrue(try second.session.modelContext.fetch(FetchDescriptor<Asset>()).isEmpty)

        let firstRecovery = try PackFinalizationRecoveryAdapterV1(
            dependencies: first.dependencies,
            profile: profile,
            legacyModelContext: first.session.modelContext
        )
        let secondRecovery = try PackFinalizationRecoveryAdapterV1(
            dependencies: second.dependencies,
            profile: profile,
            legacyModelContext: second.session.modelContext
        )
        let firstOutcome = try await firstRecovery.reconcile()
        let secondOutcome = try await secondRecovery.reconcile()
        XCTAssertEqual(firstOutcome.workspaceID, first.dependencies.workspaceID)
        XCTAssertEqual(secondOutcome.workspaceID, second.dependencies.workspaceID)
        XCTAssertTrue(firstOutcome.summary.recoveredDraftRecordIDs.isEmpty)
        XCTAssertTrue(secondOutcome.summary.completedRecordIDs.isEmpty)
        XCTAssertFalse(firstOutcome.preservesReservedLegacyRawWriteDebt)
        XCTAssertTrue(firstOutcome.zeroFeatureWriteClosureClaimed)
    }

    @MainActor
    func testV9_18ProductionRootCreatesFirstSignThroughCurrentCanonicalWriter() async throws {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let harness = try makeHarness("production-root", profile: profile)
        defer { harness.cleanup(fileManager: fileManager) }
        let diagnostics = DiagnosticsStore(applicationSupportURL: harness.root)
        let root = try ProductionCompositionRoot(
            storeSession: harness.coordinator,
            diagnosticsStore: diagnostics,
            profileRegistry: harness.dependencies.profileRegistry
        )
        let workflow = try root.makeSignWorkflow(signPack: profile.package)

        let before = try workflow.lifecycle.writer.currentRevision()
        let snapshot = try await workflow.firstSign.create(firstSignInput("Production"))
        let after = try workflow.lifecycle.writer.currentRevision()
        let rows = try harness.coordinator.modelContext.fetch(
            FetchDescriptor<MutationReceiptRow>()
        )
        let row = try XCTUnwrap(rows.first)
        let receipt = try XCTUnwrap(try workflow.lifecycle.writer.durableReceipt(
            mutationID: try MutationIDV1(rawValue: row.mutationID)
        ))

        XCTAssertEqual(snapshot.packID, profile.release.packageID)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(row.commandKind, WorkspaceCommandKindV1.createFirstSign.rawValue)
        XCTAssertEqual(after.revision, before.revision + 1)
        XCTAssertEqual(receipt.resultingRevision.workspaceRevision, after.revision)
        XCTAssertEqual(receipt.resultingRevision.generationID, harness.session.generationID)
    }

    @MainActor
    func testV9_18ProductionRootRejectsMismatchedRegistryWithoutMutation() throws {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let harness = try makeHarness("production-root-mismatch", profile: profile)
        defer { harness.cleanup(fileManager: fileManager) }
        let alternate = try alternatePackage()
        let alternateRegistry = try WorkspacePackageLifecycleCompatibilityV1
            .legacyV3Registry(package: alternate)
        XCTAssertThrowsError(
            try harness.coordinator.packageLifecycleDependencies(
                profileRegistry: alternateRegistry
            )
        ) {
            XCTAssertEqual($0 as? WorkspaceMutationContractFailureV1, .invalidPlan)
        }
        let root = try ProductionCompositionRoot(
            storeSession: harness.coordinator,
            diagnosticsStore: DiagnosticsStore(applicationSupportURL: harness.root),
            profileRegistry: alternateRegistry
        )
        let before = try harness.coordinator.workspaceWriter.currentRevision()

        XCTAssertThrowsError(try root.makeSignWorkflow(signPack: profile.package))

        XCTAssertEqual(try harness.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(
            try harness.coordinator.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            0
        )
        XCTAssertEqual(
            try harness.coordinator.modelContext.fetchCount(FetchDescriptor<Asset>()),
            0
        )
    }

    @MainActor
    func testV9_18ProductionRootRebindsOnlyAfterRealGenerationReplacement() async throws {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let harness = try makeHarness("production-root-replacement", profile: profile)
        defer { harness.cleanup(fileManager: fileManager) }
        let diagnostics = DiagnosticsStore(applicationSupportURL: harness.root)
        let oldRoot = try ProductionCompositionRoot(
            storeSession: harness.coordinator,
            diagnosticsStore: diagnostics,
            profileRegistry: harness.dependencies.profileRegistry
        )
        let oldWorkflow = try oldRoot.makeSignWorkflow(signPack: profile.package)
        let retiredModelContext = harness.coordinator.modelContext
        let factory = StoreGenerationFactory(applicationSupportURL: harness.root)
        let oldPointer = try restorePointer(
            from: factory.currentGenerationPointerV3(
                expectedGenerationID: harness.session.generationID
            )
        )
        let authority = try factory.makeRestoreGenerationAuthority()
        let created = try factory.createEmptyEraseGeneration(
            id: UUID(),
            expectedOldPointer: oldPointer,
            identity: harness.session.workspaceIdentity,
            authority: authority
        )
        try factory.publishEmptyEraseGeneration(
            expectedOldPointer: oldPointer,
            targetPointer: created.pointer,
            expectedEmptyLedger: created.ledgerProof,
            authority: authority
        )
        let replacement = try factory.openOrBootstrapCurrent()
        try harness.coordinator.activateValidating(session: replacement)

        XCTAssertThrowsError(try oldWorkflow.lifecycle.writer.currentRevision()) { error in
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .writerInvalidated)
        }
        do {
            _ = try await oldWorkflow.firstSign.create(firstSignInput("Stale"))
            XCTFail("the old composed first-sign writer must be invalidated")
        } catch {
            XCTAssertEqual(error as? FirstSignCoordinatorError, .saveFailed)
        }
        XCTAssertEqual(
            try retiredModelContext.fetchCount(FetchDescriptor<Asset>()),
            0
        )
        XCTAssertEqual(
            try retiredModelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            0
        )
        XCTAssertEqual(
            try replacement.modelContext.fetchCount(FetchDescriptor<Asset>()),
            0
        )
        XCTAssertEqual(
            try replacement.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            0
        )

        let newRoot = try ProductionCompositionRoot(
            storeSession: harness.coordinator,
            diagnosticsStore: diagnostics,
            profileRegistry: try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        )
        let newWorkflow = try newRoot.makeSignWorkflow(signPack: profile.package)
        let createdSnapshot = try await newWorkflow.firstSign.create(firstSignInput("Replacement"))
        let newRevision = try newWorkflow.lifecycle.writer.currentRevision()

        XCTAssertEqual(createdSnapshot.signLabel, "Replacement Sign")
        XCTAssertEqual(newRevision.generationID, replacement.generationID)
        XCTAssertEqual(newRevision.revision, 1)
        XCTAssertEqual(
            try replacement.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            1
        )
    }

    @MainActor
    private func makeHarness(
        _ label: String,
        profile: WorkspacePackageLifecycleProfileV1
    ) throws -> Harness {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V9_18PackLifecycleIntegrationTests-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        let session = try StoreGenerationFactory(
            applicationSupportURL: root
        ).openOrBootstrapCurrent()
        let shippingProfile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(
            profiles: shippingProfile.release == profile.release
                ? [profile]
                : [shippingProfile, profile]
        )
        let coordinator = try StoreSessionCoordinator(
            validatingSession: session,
            lifecycleProfileRegistry: registry
        )
        let dependencies = try coordinator.packageLifecycleDependencies()
        return Harness(
            root: root,
            session: session,
            coordinator: coordinator,
            dependencies: dependencies
        )
    }

    private func alternatePackage() throws -> SignPack {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V21P03C01AlternatePackV1",
                withExtension: "json",
                subdirectory: "Fixtures/V21/Packs"
            ) ?? bundle.url(
                forResource: "V21P03C01AlternatePackV1",
                withExtension: "json"
            )
        )
        let raw = try Data(contentsOf: url)
        guard raw.last == 0x0A else { throw TestFailure.invalidFixture }
        let package = try InspectionPackageCanonicalCodecV2.decode(Data(raw.dropLast()))
        let presentation = package.presentation
        return SignPack(
            schemaVersion: package.schemaVersion,
            packID: package.packageID,
            contentVersion: package.contentVersion,
            nouns: .init(
                asset: .init(
                    singular: presentation.assetSingular,
                    plural: presentation.assetPlural
                ),
                check: .init(
                    singular: presentation.checkSingular,
                    plural: presentation.checkPlural
                ),
                issue: .init(
                    singular: presentation.issueSingular,
                    plural: presentation.issuePlural
                )
            ),
            evidencePurposes: presentation.evidencePurposes.map {
                .init(key: $0.key, display: $0.display, instruction: $0.instruction)
            },
            acknowledgements: presentation.acknowledgements.map {
                .init(key: $0.key, copy: $0.copy, version: $0.version)
            },
            issueLabels: presentation.issueLabels.map {
                .init(key: $0.key, display: $0.display)
            },
            couldNotVerifyReasons: .init(
                version: presentation.couldNotVerifyRegistryVersion,
                entries: presentation.couldNotVerifyReasons.map {
                    .init(key: $0.key, display: $0.display)
                }
            ),
            stageDisplays: presentation.stageDisplays.map {
                .init(key: $0.key, display: $0.display)
            },
            outcomeDisplays: presentation.outcomeDisplays.map {
                .init(key: $0.key, display: $0.display)
            },
            disclaimer: presentation.disclaimer
        )
    }

    private func firstSignInput(_ label: String) -> FirstSignInput {
        FirstSignInput(
            siteLabel: "\(label) Site",
            signLabel: "\(label) Sign",
            address: "10 Main Street",
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true
        )
    }

    private func restorePointer(
        from pointer: CurrentGenerationPointerV3
    ) throws -> RestorePointerIdentityV1 {
        RestorePointerIdentityV1(
            generationID: try XCTUnwrap(UUID(uuidString: pointer.generationID)),
            generationManifestSHA256: pointer.generationManifestSHA256,
            knownReplicaIDs: Set(try pointer.knownReplicaIDs.map {
                try XCTUnwrap(UUID(uuidString: $0))
            }),
            workspaceID: try XCTUnwrap(UUID(uuidString: pointer.workspaceID)),
            replicaID: try XCTUnwrap(UUID(uuidString: pointer.replicaID))
        )
    }

    private func makeFirstAssetCommand(
        label: String,
        mutationID: MutationIDV1,
        package: SignPack = .illuminatedSignV1
    ) throws -> WorkspaceCommandV1 {
        let siteID = UUID()
        let placementEventID = UUID()
        return .createFirstSign(FirstSignMutationV1(
            siteID: siteID,
            newSite: .init(
                id: siteID,
                label: "\(label) Site",
                address: nil,
                timeZoneID: "America/New_York"
            ),
            assetID: UUID(),
            assetLabel: label,
            packID: package.packID,
            packSchemaVersion: package.schemaVersion,
            packContentVersion: package.contentVersion,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            initialPlacementMutationID: mutationID,
            initialPlacementEventID: placementEventID,
            initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                rawValue: UUID()
            )
        ))
    }

    @MainActor
    private func request(
        mutationID: MutationIDV1,
        command: WorkspaceCommandV1,
        writer: WorkspaceWriterV1
    ) throws -> WorkspaceMutationRequestV1 {
        let current = try writer.currentRevision()
        let identities = try commandTargets(command)
        let known = Dictionary(
            uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) }
        )
        let scoped = try WorkspaceRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            revision: current.revision,
            entityRevisions: identities.map {
                WorkspaceEntityRevisionV1(identity: $0, revision: known[$0, default: 0])
            }
        )
        return WorkspaceMutationRequestV1(
            mutationID: mutationID,
            expectedRevision: WorkspaceExpectedRevisionV1(snapshot: scoped),
            command: command
        )
    }

    private func commandTargets(
        _ command: WorkspaceCommandV1
    ) throws -> [WorkspaceEntityIdentityV1] {
        guard case let .createFirstSign(value) = command else {
            throw TestFailure.unsupportedCommand
        }
        var identities = try [
            WorkspaceEntityIdentityV1(kind: .site, id: value.siteID),
            WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID),
        ]
        if let placementEventID = value.initialPlacementEventID {
            identities.append(try WorkspaceEntityIdentityV1(
                kind: .assetPlacementEvent,
                id: placementEventID
            ))
        }
        return identities
    }

    private func assertPackageOutcomeParity(
        profile: WorkspacePackageLifecycleProfileV1,
        package: SignPack,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let profiles = profile.stages
            .flatMap(\.outcomes)
            .filter { $0.role != .workRecorded }
        XCTAssertEqual(
            Set(profiles.map(\.key)),
            Set(package.outcomeDisplays.map(\.key)),
            file: file,
            line: line
        )
        for outcome in package.outcomeDisplays {
            XCTAssertEqual(
                Set(profiles.filter { $0.key == outcome.key }.map(\.display)),
                Set([outcome.display]),
                file: file,
                line: line
            )
        }
    }
}

private actor CompletionReadAuthentication: LocalAuthenticationClient {
    private(set) var count = 0
    func availability() -> LocalAuthenticationAvailabilityV1 { .systemValue(status: .available, biometry: .faceID) }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        count += 1
        return .authenticated
    }
    func cancel(attemptID: UUID) {}
}

@MainActor
private struct Harness {
    let root: URL
    let session: StoreGenerationSession
    let coordinator: StoreSessionCoordinator
    let dependencies: WorkspacePackageLifecycleDependenciesV1

    func cleanup(fileManager: FileManager) {
        try? coordinator.invalidateAndReleaseWriter()
        try? fileManager.removeItem(at: root)
    }
}

private enum TestFailure: Error {
    case invalidFixture
    case unsupportedCommand
}

extension V9_18PackLifecycleIntegrationTests {
    func testV23P03C18WorkflowChangeUsesCanonicalSemanticIdentity() throws {
        let change = try PackageSemanticChangeV1(
            kind: .workflowNodeChanged,
            stableSubjectID: "c18.workflow.node"
        )
        XCTAssertEqual(change.stableKey, "WORKFLOW_NODE_CHANGED:c18.workflow.node")
        XCTAssertEqual(
            PackageEvolutionLifecycleV1.interruption,
            "OLD_COMPLETE_OR_NEW_COMPLETE_NEVER_HYBRID"
        )
    }
}

extension V9_18PackLifecycleIntegrationTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}

extension V9_18PackLifecycleIntegrationTests {
    func testC23FieldReferencePackAnchor() throws {
        XCTAssertEqual(FieldReferencePackLifecycleV1.persistentFamilies, [
            "FieldReferenceReleaseV1", "FieldReferenceBindingV1"
        ])
        XCTAssertEqual(FieldReferencePackLifecycleV1.stagingPersistence, "DERIVED_ONLY")
    }
}
extension V9_18PackLifecycleIntegrationTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(PersistentSchemaV24.models.count, 87)
        XCTAssertEqual(SurveyDefinitionLifecycleV1.importDisposition, "QUARANTINE_THEN_NEW_DRAFT_IDENTITY")
        XCTAssertEqual(SurveyDefinitionLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
    }
}
extension V9_18PackLifecycleIntegrationTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_18PackLifecycleIntegrationTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_18PackLifecycleIntegrationTests_swift_Tests: XCTestCase {
    func testC47V918PackLifecycleIntegrationTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_18PackLifecycleIntegrationTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_18PackLifecycleIntegrationTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_18PackLifecycleIntegrationTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_18PackLifecycleIntegrationTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_18PackLifecycleIntegrationTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_18PackLifecycleIntegrationTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_18PackLifecycleIntegrationTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityContractPersistenceEnrollmentV2.persistentFamilies.count, 6)
        XCTAssertTrue(ActivityContractPersistenceEnrollmentV2.usesSoleWorkspaceWriter)
    }
}

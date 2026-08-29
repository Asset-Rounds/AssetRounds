import CryptoKit
import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V9_12WorkflowGraphTests: XCTestCase {
    func testV9_12G01PositiveWorkflowGraphMatrixValidates() throws {
        let corpus = try loadCorpus()
        XCTAssertTrue(corpus.testOnly)
        XCTAssertEqual(corpus.schema, "V21P03C02WorkflowGraphCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.failureDisposition, "FAIL_CLOSED")
        XCTAssertEqual(corpus.nodeKinds, WorkflowNodeKindV1.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(corpus.predicateKinds, BranchPredicateKindV1.allCases.map(\.rawValue).sorted())
        assertLimits(corpus.limits)

        let predicates = try predicateMatrix()
        XCTAssertEqual(predicates.map(\.kind.rawValue).sorted(), corpus.predicateKinds)
        for predicate in predicates {
            let definition = try makeWorkflow(
                workflowID: corpus.workflowID,
                predicate: predicate
            )
            let receipt = try WorkflowGraphValidatorV1.validate(definition)
            XCTAssertTrue(receipt.valid)
            XCTAssertEqual(receipt.workflowID, corpus.workflowID)
            XCTAssertEqual(receipt.nodeCount, 11)
            XCTAssertEqual(receipt.branchCount, 2)
            XCTAssertEqual(receipt.repeatGroupCount, 1)
            XCTAssertEqual(receipt.orderedNodeIDs, definition.nodes.map(\.nodeID).sorted())
            XCTAssertLessThanOrEqual(receipt.maximumObservedDepth, corpus.limits.maximumGraphDepth)
        }

        let multiNodeBody = try makeWorkflow(
            workflowID: corpus.workflowID,
            predicate: predicates[0]
        )
        XCTAssertEqual(
            corpus.repeatFixture.multiNodeBodyIDs,
            ["node.body.entry", "node.body.exit", "node.body.interior"]
        )
        XCTAssertTrue(Set(corpus.repeatFixture.multiNodeBodyIDs).isSubset(
            of: Set(multiNodeBody.nodes.map(\.nodeID))
        ))

        let nested = try nestedRepeatWorkflow(predicate: predicates[0])
        let nestedReceipt = try WorkflowGraphValidatorV1.validate(nested)
        XCTAssertEqual(nestedReceipt.repeatGroupCount, corpus.repeatFixture.nestedRepeatCount)
        XCTAssertEqual(
            Set(corpus.repeatFixture.nestedBodyIDs),
            Set(["node.outer.entry", "node.inner.repeat", "node.inner.branch",
                 "node.inner.exit", "node.outer.exit"])
        )
        XCTAssertTrue(Set(corpus.repeatFixture.nestedBodyIDs).isSubset(
            of: Set(nestedReceipt.orderedNodeIDs)
        ))

        let selection = try BranchPredicateV1(
            kind: .equals,
            fieldID: "field.condition",
            optionID: "option.pass"
        )
        let destinations = WorkflowBranchDestinationsV1(
            trueNodeID: corpus.truthDestinations.trueNodeID,
            falseNodeID: corpus.truthDestinations.falseNodeID,
            unknownNodeID: corpus.truthDestinations.unknownNodeID
        )
        try destinations.validate()
        let truthMatrix: [(WorkflowFactValueV1, BranchTruthValueV1, String)] = [
            (.option("option.pass"), .trueValue, corpus.truthDestinations.trueNodeID),
            (.option("option.fail"), .falseValue, corpus.truthDestinations.falseNodeID),
            (.unknown, .unknown, corpus.truthDestinations.unknownNodeID),
        ]
        for (fact, truth, expectedDestination) in truthMatrix {
            let result = selection.evaluate(facts: ["field.condition": fact])
            XCTAssertEqual(result, truth)
            XCTAssertEqual(destinations.destination(for: result), expectedDestination)
        }

        let repeatID = try RepeatInstanceIDV1(corpus.repeatFixture.instanceID)
        let active = try RepeatInstanceStateV1(
            instanceID: repeatID,
            repeatNodeID: corpus.repeatFixture.repeatNodeID,
            stableOrder: corpus.repeatFixture.stableOrder
        )
        let inactive = try active.invalidatedByPath()
        let review = try inactive.reactivated()
        XCTAssertEqual([active.activity, inactive.activity, review.activity].map(\.rawValue), corpus.repeatFixture.activitySequence)
        XCTAssertEqual(inactive.instanceID, active.instanceID)
        XCTAssertEqual(review.instanceID, active.instanceID)
        XCTAssertEqual(review.stableOrder, active.stableOrder)
        XCTAssertEqual(review.repeatNodeID, active.repeatNodeID)
        XCTAssertTrue(active.satisfiesCompletion)
        XCTAssertTrue(active.includedInReporting)
        XCTAssertFalse(active.requiresReview)
        XCTAssertFalse(inactive.satisfiesCompletion)
        XCTAssertFalse(inactive.includedInReporting)
        XCTAssertFalse(inactive.requiresReview)
        XCTAssertFalse(review.satisfiesCompletion)
        XCTAssertFalse(review.includedInReporting)
        XCTAssertTrue(review.requiresReview)
    }

    func testV9_12A01CycleCountDepthPredicateUnknownAndMissingFailClosed() throws {
        let corpus = try loadCorpus()
        let predicate = try BranchPredicateV1(kind: .exists, fieldID: "field.condition")
        let valid = try makeWorkflow(workflowID: corpus.workflowID, predicate: predicate)

        assertKernelFailure(.cycleDetected) {
            _ = try WorkflowGraphValidatorV1.validate(
                replacingNode(
                    in: valid,
                    nodeID: "node.review",
                    with: try WorkflowNodeV1(
                        nodeID: "node.review",
                        kind: .review,
                        localizationKey: "workflow.review",
                        outgoingNodeIDs: ["node.section"]
                    )
                )
            )
        }
        assertKernelFailure(.limitExceeded) {
            _ = try WorkflowGraphValidatorV1.validate(
                linearWorkflow(nodeCount: WorkflowGrammarLimitsV1.maximumNodeCount + 1)
            )
        }
        assertKernelFailure(.limitExceeded) {
            _ = try WorkflowGraphValidatorV1.validate(
                WorkflowDefinitionV1(
                    workflowID: valid.workflowID,
                    entryNodeID: valid.entryNodeID,
                    declaredFieldIDs: (0...WorkflowGrammarLimitsV1.maximumFieldCount).map {
                        String(format: "field.%03d", $0)
                    },
                    nodes: valid.nodes
                )
            )
        }
        assertKernelFailure(.limitExceeded) {
            _ = try WorkflowGraphValidatorV1.validate(
                linearWorkflow(nodeCount: WorkflowGrammarLimitsV1.maximumGraphDepth + 1)
            )
        }
        assertKernelFailure(.missingTarget) {
            _ = try WorkflowGraphValidatorV1.validate(
                replacingNode(
                    in: valid,
                    nodeID: "node.section",
                    with: try WorkflowNodeV1(
                        nodeID: "node.section",
                        kind: .section,
                        localizationKey: "workflow.section",
                        outgoingNodeIDs: ["node.missing"]
                    )
                )
            )
        }
        let missingFieldPredicate = try BranchPredicateV1(
            kind: .exists,
            fieldID: "field.missing"
        )
        assertKernelFailure(.missingFieldID) {
            _ = try WorkflowGraphValidatorV1.validate(
                makeWorkflow(workflowID: corpus.workflowID, predicate: missingFieldPredicate)
            )
        }
        assertKernelFailure(.forwardPredicateReference) {
            _ = try WorkflowGraphValidatorV1.validate(
                forwardReferenceWorkflow(predicate: predicate)
            )
        }

        let escapedBody = try WorkflowNodeV1(
            nodeID: "node.body.entry", kind: .branch,
            predicate: predicate,
            branchDestinations: WorkflowBranchDestinationsV1(
                trueNodeID: "node.review",
                falseNodeID: "node.body.interior",
                unknownNodeID: "node.body.interior"
            ),
            outgoingNodeIDs: ["node.review", "node.body.interior", "node.body.interior"]
        )
        assertKernelFailure(.invalidCardinality) {
            _ = try WorkflowGraphValidatorV1.validate(
                replacingNode(in: valid, nodeID: "node.body.entry", with: escapedBody)
            )
        }
        let outsideEntryBranch = try WorkflowNodeV1(
            nodeID: "node.branch", kind: .branch,
            predicate: predicate,
            branchDestinations: WorkflowBranchDestinationsV1(
                trueNodeID: "node.repeat",
                falseNodeID: "node.body.entry",
                unknownNodeID: "node.terminal"
            ),
            outgoingNodeIDs: ["node.repeat", "node.body.entry", "node.terminal"]
        )
        assertKernelFailure(.invalidCardinality) {
            _ = try WorkflowGraphValidatorV1.validate(
                replacingNode(in: valid, nodeID: "node.branch", with: outsideEntryBranch)
            )
        }

        let nested = try nestedRepeatWorkflow(predicate: predicate)
        let nestedEscape = try WorkflowNodeV1(
            nodeID: "node.inner.branch", kind: .branch,
            predicate: predicate,
            branchDestinations: WorkflowBranchDestinationsV1(
                trueNodeID: "node.outer.exit",
                falseNodeID: "node.inner.exit",
                unknownNodeID: "node.inner.exit"
            ),
            outgoingNodeIDs: ["node.outer.exit", "node.inner.exit", "node.inner.exit"]
        )
        assertKernelFailure(.invalidCardinality) {
            _ = try WorkflowGraphValidatorV1.validate(
                replacingNode(in: nested, nodeID: "node.inner.branch", with: nestedEscape)
            )
        }

        var deepest = predicate
        for _ in 1..<WorkflowGrammarLimitsV1.maximumPredicateDepth {
            deepest = try BranchPredicateV1(kind: .not, operands: [deepest])
        }
        assertKernelFailure(.limitExceeded) {
            _ = try BranchPredicateV1(kind: .not, operands: [deepest])
        }

        let convergentDestinations = WorkflowBranchDestinationsV1(
            trueNodeID: "node.repeat",
            falseNodeID: "node.repeat",
            unknownNodeID: "node.terminal"
        )
        try convergentDestinations.validate()
        let convergentBranch = try WorkflowNodeV1(
                nodeID: "node.branch",
                kind: .branch,
                predicate: predicate,
                branchDestinations: convergentDestinations,
                outgoingNodeIDs: ["node.repeat", "node.repeat", "node.terminal"]
        )
        XCTAssertEqual(
            convergentDestinations.destination(for: .trueValue),
            convergentDestinations.destination(for: .falseValue)
        )
        XCTAssertNoThrow(try WorkflowGraphValidatorV1.validate(
            replacingNode(in: valid, nodeID: "node.branch", with: convergentBranch)
        ))

        let canonical = try WorkflowDefinitionCanonicalCodecV1.encode(valid)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        )
        var unknownNode = object
        var unknownNodes = try XCTUnwrap(unknownNode["nodes"] as? [[String: Any]])
        let sectionIndex = try XCTUnwrap(
            unknownNodes.firstIndex { $0["nodeID"] as? String == "node.section" }
        )
        unknownNodes[sectionIndex]["kind"] = "EXECUTABLE_SCRIPT"
        unknownNode["nodes"] = unknownNodes
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                WorkflowDefinitionV1.self,
                from: try canonicalJSON(unknownNode)
            )
        )

        var unknownPredicate = object
        var predicateNodes = try XCTUnwrap(unknownPredicate["nodes"] as? [[String: Any]])
        let branchIndex = try XCTUnwrap(
            predicateNodes.firstIndex { $0["nodeID"] as? String == "node.branch" }
        )
        var predicateObject = try XCTUnwrap(
            predicateNodes[branchIndex]["predicate"] as? [String: Any]
        )
        predicateObject["kind"] = "ARBITRARY_EXPRESSION"
        predicateNodes[branchIndex]["predicate"] = predicateObject
        unknownPredicate["nodes"] = predicateNodes
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                WorkflowDefinitionV1.self,
                from: try canonicalJSON(unknownPredicate)
            )
        )
        XCTAssertEqual(Set(corpus.negativeCases), Set([
            "COUNT_LIMIT", "CYCLE", "DEPTH_LIMIT", "FIELD_COUNT_LIMIT",
            "FORWARD_PREDICATE_REFERENCE",
            "MISSING_FIELD_ID", "MISSING_TARGET", "NESTED_REPEAT_ESCAPE",
            "PREDICATE_DEPTH_LIMIT",
            "REPEAT_BODY_ESCAPE", "REPEAT_BODY_OUTSIDE_ENTRY",
            "UNKNOWN_NODE_KIND", "UNKNOWN_PREDICATE_KIND",
        ]))
    }

    func testV9_12H01PublishedPackageReleaseIsImmutable() throws {
        let workflow = try makeWorkflow(
            workflowID: try loadCorpus().workflowID,
            predicate: try BranchPredicateV1(kind: .exists, fieldID: "field.condition")
        )
        let draft = try BundledInspectionPackageRegistryV2.shippingDraftRelease(
            workflow: workflow
        )
        let tested = try InspectionPackageReleasePublisherV1.test(draft)
        let published = try InspectionPackageReleasePublisherV1.publish(tested)
        let adopted = try InspectionPackageReleasePublisherV1.adopt(published)

        XCTAssertEqual(draft.packageReleaseID, tested.release.packageReleaseID)
        XCTAssertEqual(tested.release.packageReleaseID, published.release.packageReleaseID)
        XCTAssertEqual(published, adopted)
        XCTAssertEqual(draft.canonicalPackageBytes, published.release.canonicalPackageBytes)
        XCTAssertEqual(draft.canonicalWorkflowBytes, published.release.canonicalWorkflowBytes)
        XCTAssertEqual(draft.packageSHA256, published.release.packageSHA256)
        XCTAssertEqual(draft.workflowSHA256, published.release.workflowSHA256)
        XCTAssertEqual(
            [draft.state, tested.release.state, published.release.state].map(\.rawValue),
            try loadCorpus().releaseStates
        )
        assertKernelFailure(.invalidTransition) {
            _ = try InspectionPackageReleasePublisherV1.test(published.release)
        }

        var tampered = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: InspectionPackageReleaseCanonicalCodecV1.encode(published.release)
            ) as? [String: Any]
        )
        tampered["workflowSHA256"] = String(repeating: "0", count: 64)
        assertKernelFailure(.hashMismatch) {
            _ = try JSONDecoder().decode(
                InspectionPackageReleaseV1.self,
                from: canonicalJSON(tampered)
            )
        }

        var stateBypassObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: InspectionPackageReleaseCanonicalCodecV1.encode(draft)
            ) as? [String: Any]
        )
        stateBypassObject["state"] = InspectionPackageReleaseStateV1.published.rawValue
        let arbitraryPublishedBytes = try canonicalJSON(stateBypassObject)
        let arbitraryPublished = try InspectionPackageReleaseCanonicalCodecV1.decode(
            arbitraryPublishedBytes
        )
        assertKernelFailure(.invalidTransition) {
            _ = try InspectionPackageReleasePublisherV1.test(arbitraryPublished)
        }
        let acceptedBinding = try PackageReleaseBindingV1(
            bindingID: "fixture.accepted.binding.v1",
            kind: .active,
            publication: published
        )
        let otherWorkflow = try makeWorkflow(
            workflowID: "fixture.workflow.unaccepted.v1",
            predicate: try BranchPredicateV1(kind: .exists, fieldID: "field.condition")
        )
        let otherDraft = try BundledInspectionPackageRegistryV2.shippingDraftRelease(
            workflow: otherWorkflow
        )
        let otherPublication = try InspectionPackageReleasePublisherV1.publish(
            InspectionPackageReleasePublisherV1.test(otherDraft)
        )
        let otherBinding = try PackageReleaseBindingV1(
            bindingID: "fixture.unaccepted.binding.v1",
            kind: .active,
            publication: otherPublication
        )
        assertKernelFailure(.releaseNotFound) {
            _ = try InspectionPackageReleasePublisherV1.recoverPublished(
                arbitraryPublished,
                acceptedBinding: otherBinding
            )
        }
        let authorized = try InspectionPackageReleasePublisherV1.recoverPublished(
            arbitraryPublished,
            acceptedBinding: acceptedBinding
        )
        XCTAssertEqual(authorized, published)
    }

    func testV9_12I01InterruptedPublicationExposesZeroOrCompleteRelease() throws {
        let workflow = try makeWorkflow(
            workflowID: try loadCorpus().workflowID,
            predicate: try BranchPredicateV1(kind: .exists, fieldID: "field.condition")
        )
        let draft = try BundledInspectionPackageRegistryV2.shippingDraftRelease(
            workflow: workflow
        )
        let tested = try InspectionPackageReleasePublisherV1.test(draft)
        let complete = try InspectionPackageReleasePublisherV1.publish(tested)
        let boundaries = InspectionPackageReleasePublisherV1.Boundary.allCases
        XCTAssertEqual(boundaries.map(\.rawValue).sorted(), try loadCorpus().interruptionBoundaries)

        for boundary in boundaries {
            var exposedTested: InspectionPackageTestedReleaseV1? = nil
            XCTAssertThrowsError(
                try {
                    exposedTested = try InspectionPackageReleasePublisherV1.test(draft) { reached in
                        if reached == boundary {
                            throw InspectionKernelFailureV1.publicationInterrupted
                        }
                    }
                }()
            ) { error in
                XCTAssertEqual(error as? InspectionKernelFailureV1, .publicationInterrupted)
            }
            XCTAssertNil(exposedTested)
            XCTAssertEqual(try InspectionPackageReleasePublisherV1.test(draft), tested)

            var exposed: InspectionPackagePublishedReleaseV1? = nil
            XCTAssertThrowsError(
                try {
                    exposed = try InspectionPackageReleasePublisherV1.publish(tested) { reached in
                        if reached == boundary {
                            throw InspectionKernelFailureV1.publicationInterrupted
                        }
                    }
                }()
            ) { error in
                XCTAssertEqual(error as? InspectionKernelFailureV1, .publicationInterrupted)
            }
            XCTAssertNil(exposed)
            let relaunched = try InspectionPackageReleasePublisherV1.publish(tested)
            XCTAssertEqual(relaunched, complete)
        }
    }

    func testV9_12R01OlderPackageResumeUsesExactValidatedRelease() throws {
        let corpus = try loadCorpus()
        let releaseBytes = try XCTUnwrap(Data(base64Encoded: corpus.olderResume.canonicalReleaseBase64))
        let bindingBytes = try XCTUnwrap(Data(base64Encoded: corpus.olderResume.canonicalBindingBase64))
        XCTAssertEqual(Self.sha256(releaseBytes), corpus.olderResume.releaseSHA256)
        XCTAssertEqual(Self.sha256(bindingBytes), corpus.olderResume.bindingSHA256)
        let historicalRelease = try InspectionPackageReleaseCanonicalCodecV1.decode(releaseBytes)
        XCTAssertEqual(try InspectionPackageReleaseCanonicalCodecV1.encode(historicalRelease), releaseBytes)
        XCTAssertEqual(historicalRelease.packageReleaseID, corpus.olderResume.packageReleaseID)
        XCTAssertEqual(Self.sha256(historicalRelease.canonicalPackageBytes), corpus.olderResume.packageSHA256)
        XCTAssertEqual(Self.sha256(historicalRelease.canonicalWorkflowBytes), corpus.olderResume.workflowSHA256)
        let frozenBinding = try PackageReleaseBindingCanonicalCodecV1.decode(bindingBytes)
        XCTAssertEqual(try PackageReleaseBindingCanonicalCodecV1.encode(frozenBinding), bindingBytes)
        XCTAssertEqual(frozenBinding.bindingID, corpus.olderResume.bindingID)
        let historicalPublication = try InspectionPackageReleasePublisherV1.recoverPublished(
            historicalRelease,
            acceptedBinding: frozenBinding
        )
        XCTAssertNoThrow(try frozenBinding.validateResume(against: historicalPublication))

        let historicalPackage = try InspectionPackageCanonicalCodecV2.decode(
            historicalRelease.canonicalPackageBytes
        )
        let oldWorkflow = try WorkflowDefinitionCanonicalCodecV1.decode(
            historicalRelease.canonicalWorkflowBytes
        )
        let currentDraft = try InspectionPackageReleaseV1.makeDraft(
            package: historicalPackage,
            workflow: oldWorkflow
        )
        let currentTested = try InspectionPackageReleasePublisherV1.test(currentDraft)
        let currentPublication = try InspectionPackageReleasePublisherV1.publish(currentTested)
        XCTAssertEqual(currentPublication.release, historicalRelease)

        let predicate = try BranchPredicateV1(kind: .exists, fieldID: "field.condition")
        let changedWorkflow = try makeWorkflow(
            workflowID: corpus.olderResume.changedWorkflowID,
            predicate: predicate
        )
        let changedDraft = try InspectionPackageReleaseV1.makeDraft(
            package: historicalPackage,
            workflow: changedWorkflow
        )
        let changedPublication = try InspectionPackageReleasePublisherV1.publish(
            InspectionPackageReleasePublisherV1.test(changedDraft)
        )
        XCTAssertNotEqual(historicalRelease.packageReleaseID, changedPublication.release.packageReleaseID)

        for kind in PackageReleaseBindingKindV1.allCases {
            let binding = try PackageReleaseBindingV1(
                bindingID: "fixture.\(kind.rawValue.lowercased()).binding.v1",
                kind: kind,
                publication: historicalPublication
            )
            XCTAssertNoThrow(try binding.validateResume(against: historicalPublication))
            assertKernelFailure(.hashMismatch) {
                try binding.validateResume(against: changedPublication)
            }
        }
        XCTAssertEqual(PackageReleaseBindingKindV1.allCases.map(\.rawValue).sorted(), corpus.bindingKinds)

        var future = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bindingBytes) as? [String: Any]
        )
        future["schemaVersion"] = 2
        assertKernelFailure(.hashMismatch) {
            _ = try PackageReleaseBindingCanonicalCodecV1.decode(canonicalJSON(future))
        }
        var wrongHash = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bindingBytes) as? [String: Any]
        )
        wrongHash["packageSHA256"] = String(repeating: "f", count: 64)
        assertKernelFailure(.hashMismatch) {
            _ = try PackageReleaseBindingCanonicalCodecV1.decode(canonicalJSON(wrongHash))
        }

        XCTAssertEqual(historicalRelease.packageID, corpus.olderResume.packageID)
        XCTAssertEqual(InspectionKernelLifecycleV1.mode, "DECLARATION_ONLY")
        XCTAssertEqual(InspectionKernelLifecycleV1.schema, "KERNEL_CONTRACT_V1")
        XCTAssertFalse(InspectionKernelLifecycleV1.persistent)
        XCTAssertFalse(InspectionKernelLifecycleV1.migrationRequired)
        XCTAssertFalse(InspectionKernelLifecycleV1.backupRestoreRequired)
        XCTAssertFalse(InspectionKernelLifecycleV1.deleteEraseRequired)
        XCTAssertFalse(InspectionKernelLifecycleV1.exportReportEffectRequired)
        XCTAssertFalse(InspectionKernelLifecycleV1.searchRebuildReplayRequired)
        XCTAssertEqual(InspectionKernelLifecycleV1.downgradePolicy, "DORMANT_REVERT_ALLOWED")
        XCTAssertEqual(InspectionKernelLifecycleV1.interruption, "ZERO_OR_COMPLETE")
        XCTAssertEqual(InspectionKernelLifecycleV1.idempotentReceipt, "EXACT_CANONICAL_BYTES_ADOPTION")

        let raw = try Data(contentsOf: fixtureURL())
        XCTAssertEqual(Self.sha256(raw), "1676ba3644de68526dddc0155a5a5392cdc21f83bfaa007bff53d14f1da1be75")
    }

    private func predicateMatrix() throws -> [BranchPredicateV1] {
        let exists = try BranchPredicateV1(kind: .exists, fieldID: "field.condition")
        let known = try BranchPredicateV1(kind: .isKnown, fieldID: "field.condition")
        let equals = try BranchPredicateV1(
            kind: .equals,
            fieldID: "field.condition",
            optionID: "option.pass"
        )
        let inSet = try BranchPredicateV1(
            kind: .inSet,
            fieldID: "field.condition",
            optionIDs: ["option.fail", "option.pass"]
        )
        let compare = try BranchPredicateV1(
            kind: .compareFixed,
            fieldID: "field.condition",
            comparison: .greaterThanOrEqual,
            fixedValue: 1
        )
        return [
            exists,
            known,
            equals,
            inSet,
            compare,
            try BranchPredicateV1(kind: .not, operands: [exists]),
            try BranchPredicateV1(kind: .all, operands: [exists, known]),
            try BranchPredicateV1(kind: .any, operands: [equals, inSet]),
        ]
    }

    private func makeWorkflow(
        workflowID: String,
        predicate: BranchPredicateV1
    ) throws -> WorkflowDefinitionV1 {
        let destinations = WorkflowBranchDestinationsV1(
            trueNodeID: "node.repeat",
            falseNodeID: "node.review",
            unknownNodeID: "node.terminal"
        )
        return try WorkflowDefinitionV1(
            workflowID: workflowID,
            entryNodeID: "node.section",
            declaredFieldIDs: ["field.condition"],
            nodes: [
                try WorkflowNodeV1(
                    nodeID: "node.section", kind: .section,
                    localizationKey: "workflow.section",
                    outgoingNodeIDs: ["node.instruction"]
                ),
                try WorkflowNodeV1(
                    nodeID: "node.instruction", kind: .instruction,
                    localizationKey: "workflow.instruction",
                    outgoingNodeIDs: ["node.fact"]
                ),
                try WorkflowNodeV1(
                    nodeID: "node.fact", kind: .fact,
                    localizationKey: "workflow.fact", fieldID: "field.condition",
                    outgoingNodeIDs: ["node.evidence"]
                ),
                try WorkflowNodeV1(
                    nodeID: "node.evidence", kind: .evidenceRequest,
                    localizationKey: "workflow.evidence",
                    evidencePurposeID: "wide_context",
                    outgoingNodeIDs: ["node.branch"]
                ),
                try WorkflowNodeV1(
                    nodeID: "node.branch", kind: .branch,
                    predicate: predicate, branchDestinations: destinations,
                    outgoingNodeIDs: ["node.repeat", "node.review", "node.terminal"]
                ),
                try WorkflowNodeV1(
                    nodeID: "node.repeat", kind: .repeatGroup,
                    localizationKey: "workflow.repeat",
                    repeatBodyEntryNodeID: "node.body.entry",
                    repeatBodyExitNodeID: "node.body.exit",
                    maximumRepeatInstances: 2,
                    outgoingNodeIDs: ["node.body.entry", "node.review"]
                ),
                try WorkflowNodeV1(
                    nodeID: "node.body.entry", kind: .branch,
                    predicate: predicate,
                    branchDestinations: WorkflowBranchDestinationsV1(
                        trueNodeID: "node.body.interior",
                        falseNodeID: "node.body.interior",
                        unknownNodeID: "node.body.interior"
                    ),
                    outgoingNodeIDs: [
                        "node.body.interior", "node.body.interior", "node.body.interior",
                    ]
                ),
                try WorkflowNodeV1(
                    nodeID: "node.body.interior", kind: .instruction,
                    localizationKey: "workflow.body.interior",
                    outgoingNodeIDs: ["node.body.exit"]
                ),
                try WorkflowNodeV1(
                    nodeID: "node.body.exit", kind: .instruction,
                    localizationKey: "workflow.body.exit",
                    outgoingNodeIDs: ["node.review"]
                ),
                try WorkflowNodeV1(
                    nodeID: "node.review", kind: .review,
                    localizationKey: "workflow.review",
                    outgoingNodeIDs: ["node.terminal"]
                ),
                try WorkflowNodeV1(
                    nodeID: "node.terminal", kind: .terminal,
                    localizationKey: "workflow.terminal",
                    outgoingNodeIDs: []
                ),
            ]
        )
    }

    private func nestedRepeatWorkflow(
        predicate: BranchPredicateV1
    ) throws -> WorkflowDefinitionV1 {
        let base = try makeWorkflow(
            workflowID: "fixture.workflow.nested-repeat.v1",
            predicate: predicate
        )
        let branch = try WorkflowNodeV1(
            nodeID: "node.branch", kind: .branch,
            predicate: predicate,
            branchDestinations: WorkflowBranchDestinationsV1(
                trueNodeID: "node.outer.repeat",
                falseNodeID: "node.review",
                unknownNodeID: "node.terminal"
            ),
            outgoingNodeIDs: ["node.outer.repeat", "node.review", "node.terminal"]
        )
        let nestedNodes = [
            try WorkflowNodeV1(
                nodeID: "node.outer.repeat", kind: .repeatGroup,
                localizationKey: "workflow.outer.repeat",
                repeatBodyEntryNodeID: "node.outer.entry",
                repeatBodyExitNodeID: "node.outer.exit",
                maximumRepeatInstances: 2,
                outgoingNodeIDs: ["node.outer.entry", "node.review"]
            ),
            try WorkflowNodeV1(
                nodeID: "node.outer.entry", kind: .instruction,
                localizationKey: "workflow.outer.entry",
                outgoingNodeIDs: ["node.inner.repeat"]
            ),
            try WorkflowNodeV1(
                nodeID: "node.inner.repeat", kind: .repeatGroup,
                localizationKey: "workflow.inner.repeat",
                repeatBodyEntryNodeID: "node.inner.branch",
                repeatBodyExitNodeID: "node.inner.exit",
                maximumRepeatInstances: 2,
                outgoingNodeIDs: ["node.inner.branch", "node.outer.exit"]
            ),
            try WorkflowNodeV1(
                nodeID: "node.inner.branch", kind: .branch,
                predicate: predicate,
                branchDestinations: WorkflowBranchDestinationsV1(
                    trueNodeID: "node.inner.exit",
                    falseNodeID: "node.inner.exit",
                    unknownNodeID: "node.inner.exit"
                ),
                outgoingNodeIDs: ["node.inner.exit", "node.inner.exit", "node.inner.exit"]
            ),
            try WorkflowNodeV1(
                nodeID: "node.inner.exit", kind: .instruction,
                localizationKey: "workflow.inner.exit",
                outgoingNodeIDs: ["node.outer.exit"]
            ),
            try WorkflowNodeV1(
                nodeID: "node.outer.exit", kind: .instruction,
                localizationKey: "workflow.outer.exit",
                outgoingNodeIDs: ["node.review"]
            ),
        ]
        return try WorkflowDefinitionV1(
            workflowID: base.workflowID,
            entryNodeID: base.entryNodeID,
            declaredFieldIDs: base.declaredFieldIDs,
            nodes: base.nodes.filter {
                ["node.section", "node.instruction", "node.fact", "node.evidence",
                 "node.review", "node.terminal"].contains($0.nodeID)
            } + [branch] + nestedNodes
        )
    }

    private func forwardReferenceWorkflow(
        predicate: BranchPredicateV1
    ) throws -> WorkflowDefinitionV1 {
        let base = try makeWorkflow(workflowID: "fixture.workflow.forward.v1", predicate: predicate)
        let section = try WorkflowNodeV1(
            nodeID: "node.section", kind: .section,
            localizationKey: "workflow.section", outgoingNodeIDs: ["node.instruction"]
        )
        let instruction = try WorkflowNodeV1(
            nodeID: "node.instruction", kind: .instruction,
            localizationKey: "workflow.instruction", outgoingNodeIDs: ["node.branch"]
        )
        let branch = try WorkflowNodeV1(
            nodeID: "node.branch", kind: .branch,
            predicate: predicate,
            branchDestinations: WorkflowBranchDestinationsV1(
                trueNodeID: "node.fact",
                falseNodeID: "node.review",
                unknownNodeID: "node.terminal"
            ),
            outgoingNodeIDs: ["node.fact", "node.review", "node.terminal"]
        )
        let fact = try WorkflowNodeV1(
            nodeID: "node.fact", kind: .fact,
            localizationKey: "workflow.fact", fieldID: "field.condition",
            outgoingNodeIDs: ["node.evidence"]
        )
        let evidence = try WorkflowNodeV1(
            nodeID: "node.evidence", kind: .evidenceRequest,
            localizationKey: "workflow.evidence", evidencePurposeID: "wide_context",
            outgoingNodeIDs: ["node.repeat"]
        )
        return try WorkflowDefinitionV1(
            workflowID: base.workflowID,
            entryNodeID: section.nodeID,
            declaredFieldIDs: base.declaredFieldIDs,
            nodes: [section, instruction, branch, fact, evidence]
                + base.nodes.filter {
                    ["node.repeat", "node.body.entry", "node.body.interior",
                     "node.body.exit", "node.review", "node.terminal"]
                        .contains($0.nodeID)
                }
        )
    }

    private func replacingNode(
        in definition: WorkflowDefinitionV1,
        nodeID: String,
        with replacement: WorkflowNodeV1
    ) throws -> WorkflowDefinitionV1 {
        try WorkflowDefinitionV1(
            workflowID: definition.workflowID,
            entryNodeID: definition.entryNodeID,
            declaredFieldIDs: definition.declaredFieldIDs,
            nodes: definition.nodes.map { $0.nodeID == nodeID ? replacement : $0 }
        )
    }

    private func linearWorkflow(nodeCount: Int) throws -> WorkflowDefinitionV1 {
        var nodes: [WorkflowNodeV1] = []
        for index in 0..<nodeCount {
            let nodeID = String(format: "linear.%03d", index)
            if index == nodeCount - 1 {
                nodes.append(try WorkflowNodeV1(
                    nodeID: nodeID,
                    kind: .terminal,
                    localizationKey: "workflow.terminal",
                    outgoingNodeIDs: []
                ))
            } else {
                nodes.append(try WorkflowNodeV1(
                    nodeID: nodeID,
                    kind: index == 0 ? .section : .instruction,
                    localizationKey: "workflow.linear",
                    outgoingNodeIDs: [String(format: "linear.%03d", index + 1)]
                ))
            }
        }
        return try WorkflowDefinitionV1(
            workflowID: "fixture.workflow.linear.v1",
            entryNodeID: "linear.000",
            declaredFieldIDs: [],
            nodes: nodes
        )
    }

    private func assertLimits(_ value: V912Corpus.Limits) {
        XCTAssertEqual(value.maximumNodeCount, WorkflowGrammarLimitsV1.maximumNodeCount)
        XCTAssertEqual(value.maximumEdgeCount, WorkflowGrammarLimitsV1.maximumEdgeCount)
        XCTAssertEqual(value.maximumFieldCount, WorkflowGrammarLimitsV1.maximumFieldCount)
        XCTAssertEqual(value.maximumGraphDepth, WorkflowGrammarLimitsV1.maximumGraphDepth)
        XCTAssertEqual(value.maximumBranchCount, WorkflowGrammarLimitsV1.maximumBranchCount)
        XCTAssertEqual(value.maximumPredicateDepth, WorkflowGrammarLimitsV1.maximumPredicateDepth)
        XCTAssertEqual(value.maximumPredicateOperands, WorkflowGrammarLimitsV1.maximumPredicateOperands)
        XCTAssertEqual(value.maximumSetOperandCount, WorkflowGrammarLimitsV1.maximumSetOperandCount)
        XCTAssertEqual(value.maximumRepeatCount, WorkflowGrammarLimitsV1.maximumRepeatCount)
        XCTAssertEqual(value.maximumTotalExecutions, WorkflowGrammarLimitsV1.maximumTotalExecutions)
    }

    private func assertKernelFailure(
        _ expected: InspectionKernelFailureV1,
        _ operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? InspectionKernelFailureV1, expected, file: file, line: line)
        }
    }

    private func canonicalJSON(_ object: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func loadCorpus() throws -> V912Corpus {
        try JSONDecoder().decode(V912Corpus.self, from: Data(contentsOf: fixtureURL()))
    }

    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(
            bundle.url(
                forResource: "V21P03C02WorkflowGraphCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V21/InspectionKernel"
            ) ?? bundle.url(
                forResource: "V21P03C02WorkflowGraphCorpusV1",
                withExtension: "json"
            )
        )
    }

    nonisolated private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct V912Corpus: Decodable {
    struct Limits: Decodable {
        let maximumBranchCount: Int
        let maximumEdgeCount: Int
        let maximumFieldCount: Int
        let maximumGraphDepth: Int
        let maximumNodeCount: Int
        let maximumPredicateDepth: Int
        let maximumPredicateOperands: Int
        let maximumRepeatCount: Int
        let maximumSetOperandCount: Int
        let maximumTotalExecutions: Int
    }
    struct TruthDestinations: Decodable {
        let falseNodeID: String
        let trueNodeID: String
        let unknownNodeID: String
        private enum CodingKeys: String, CodingKey {
            case falseNodeID = "FALSE"
            case trueNodeID = "TRUE"
            case unknownNodeID = "UNKNOWN"
        }
    }
    struct RepeatFixture: Decodable {
        let activitySequence: [String]
        let instanceID: String
        let multiNodeBodyIDs: [String]
        let nestedBodyIDs: [String]
        let nestedRepeatCount: Int
        let repeatNodeID: String
        let stableOrder: Int
    }
    struct OlderResume: Decodable {
        let bindingID: String
        let bindingSHA256: String
        let canonicalBindingBase64: String
        let canonicalReleaseBase64: String
        let changedWorkflowID: String
        let packageID: String
        let packageReleaseID: String
        let packageSHA256: String
        let releaseSHA256: String
        let workflowSHA256: String
    }
    let bindingKinds: [String]
    let failureDisposition: String
    let interruptionBoundaries: [String]
    let limits: Limits
    let negativeCases: [String]
    let nodeKinds: [String]
    let olderResume: OlderResume
    let predicateKinds: [String]
    let releaseStates: [String]
    let repeatFixture: RepeatFixture
    let schema: String
    let schemaVersion: Int
    let testOnly: Bool
    let truthDestinations: TruthDestinations
    let workflowID: String

    private enum CodingKeys: String, CodingKey {
        case bindingKinds, failureDisposition, interruptionBoundaries, limits
        case negativeCases, nodeKinds
        case olderResume, predicateKinds, releaseStates, schema, schemaVersion, testOnly
        case truthDestinations, workflowID
        case repeatFixture = "repeat"
    }
}
extension V9_12WorkflowGraphTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyDefinitionLifecycleV1.lifecycleEventPersistence, "CANONICAL_MUTATION_JOURNAL_ENVELOPE")
        XCTAssertEqual(SurveyDefinitionLifecycleV1.semanticDiffPersistence, "NONPERSISTENT")
        XCTAssertEqual(SurveyDefinitionLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
    }
}
extension V9_12WorkflowGraphTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

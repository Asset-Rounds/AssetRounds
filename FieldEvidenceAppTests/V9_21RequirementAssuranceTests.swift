import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V9_21RequirementAssuranceTests: XCTestCase {
    private let policy = String(repeating: "a", count: 64)
    private let workspaceID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let recordID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let mutationID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    func testV9_21G01RequirementEvaluationGoldenMatrixAndSiteExitDecision() throws {
        let definitions = try [
            definition("required-photo", type: "evidence", effect: .hardBlocker,
                       requiredEvidence: ["photo"]),
            definition("warning-note", type: "response", effect: .warning),
            definition("allowed-na", type: "optional", effect: .hardBlocker, allowsNA: true),
            definition("known-answer", type: "response", effect: .hardBlocker),
            definition("waivable", type: "waivable", effect: .hardBlocker,
                       waiverReasons: ["site_condition"]),
        ].sorted { $0.requirementID < $1.requirementID }
        let registry = try registry(for: definitions)
        let waiver = try RequirementWaiverV1(
            waiverID: "waiver-1", requirementID: "waivable", requirementVersion: 1,
            evaluatedRevision: 7, reasonCode: "site_condition", actorReference: "actor-ref-1",
            scopeID: "workflow-1", policySHA256: policy
        )
        let byID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.requirementID, $0) })
        let inputs = try [
            input(try XCTUnwrap(byID["allowed-na"]), state: .notApplicable),
            input(try XCTUnwrap(byID["known-answer"]), state: .satisfied),
            input(try XCTUnwrap(byID["required-photo"]), state: .satisfied,
                  evidence: [evidence("photo-1", kind: "photo", state: .valid)]),
            input(try XCTUnwrap(byID["warning-note"]), state: .satisfied),
            input(try XCTUnwrap(byID["waivable"]), state: .notSatisfied, waiver: waiver),
        ].sorted { $0.definition.requirementID < $1.definition.requirementID }
        let evaluations = try RequirementEvaluationEngineV1.evaluateAll(inputs, registry: registry)
        XCTAssertEqual(Set(evaluations.map(\.result)), [.satisfied, .notApplicable, .waived])
        let decision = try RequirementEvaluationEngineV1.completionDecision(evaluations: evaluations)
        XCTAssertEqual(decision.disposition, .permitted)
        XCTAssertTrue(decision.hardBlockerRequirementIDs.isEmpty)
        XCTAssertEqual(decision.waivedRequirementIDs, ["waivable"])
        XCTAssertEqual(RequirementExplanationProjectionV1.project(evaluations).count, 5)
        XCTAssertEqual(try corpus().goldenCases.first?.id, "V23-P03-C12-G01")
    }

    func testV9_21A01WarningNotApplicableAndReasonedWaiverRemainExplainable() throws {
        let warning = try definition("warning", type: "response", effect: .warning)
        let optional = try definition("optional", type: "optional", effect: .hardBlocker, allowsNA: true)
        let waivable = try definition("waivable", type: "waivable", effect: .hardBlocker,
                                      waiverReasons: ["site_condition"])
        let definitions = [optional, waivable, warning]
        let waiver = try RequirementWaiverV1(
            waiverID: "waiver-2", requirementID: "waivable", requirementVersion: 1,
            evaluatedRevision: 7, reasonCode: "site_condition", actorReference: "actor-ref-2",
            scopeID: "workflow-1", policySHA256: policy
        )
        let evaluations = try RequirementEvaluationEngineV1.evaluateAll([
            input(optional, state: .notApplicable),
            input(waivable, state: .notSatisfied, waiver: waiver),
            input(warning, state: .notSatisfied),
        ], registry: registry(for: definitions))
        let decision = try RequirementEvaluationEngineV1.completionDecision(evaluations: evaluations)
        XCTAssertEqual(decision.disposition, .permitted)
        XCTAssertEqual(decision.warningRequirementIDs, ["warning"])
        XCTAssertEqual(decision.notApplicableRequirementIDs, ["optional"])
        let projection = RequirementExplanationProjectionV1.project(evaluations)
        XCTAssertTrue(projection.flatMap(\.localizationKeys).contains("requirement.reason.waiver_accepted"))
    }

    func testV9_21H01StaleOrphanDuplicateContradictoryAndBypassInputsFailClosed() throws {
        let required = try definition("required", type: "evidence", effect: .hardBlocker,
                                      requiredEvidence: ["photo"])
        let duplicated = try evidence("evidence-1", kind: "photo", state: .valid)
        let invalid = try evidence("evidence-2", kind: "photo", state: .invalid)
        let input = try self.input(required, state: .satisfied,
                                   evidence: [duplicated, duplicated, invalid].sorted())
        let registry = try self.registry(for: [required])
        let evaluation = try RequirementEvaluationEngineV1.evaluate(input, registry: registry)
        XCTAssertEqual(evaluation.result, .notSatisfied)
        XCTAssertTrue(evaluation.reasonCodes.contains(.evidenceDuplicated))
        XCTAssertTrue(evaluation.reasonCodes.contains(.evidenceContradictory))
        let integrity = try RequirementIntegrityInputV1(
            canonicalEvidenceReferenceIDs: ["evidence-1", "evidence-2", "orphan-1"],
            snapshotSHA256: String(repeating: "b", count: 64),
            reportSHA256: String(repeating: "c", count: 64)
        )
        let findings = try RequirementEvaluationEngineV1.lint(
            inputs: [input], evaluations: [evaluation], integrity: integrity
        )
        XCTAssertTrue(findings.contains { $0.kind == .orphanEvidenceReference })
        XCTAssertTrue(findings.contains { $0.kind == .duplicateEvidenceReference })
        XCTAssertTrue(findings.contains { $0.kind == .contradictoryEvidence })
        XCTAssertTrue(findings.contains {
            $0.kind == .invalidState && $0.reasonCode == "evidence_invalid"
        })
        XCTAssertTrue(findings.contains { $0.kind == .snapshotReportDivergence })
        XCTAssertEqual(try RequirementEvaluationEngineV1.completionDecision(evaluations: [evaluation]).disposition, .blocked)
        XCTAssertThrowsError(try RequirementEvaluatorRegistryV1(rules: []))

        let waivableEvidence = try definition(
            "waivable-evidence", type: "evidence", effect: .hardBlocker,
            requiredEvidence: ["photo"], waiverReasons: ["site_condition"]
        )
        let waiver = try RequirementWaiverV1(
            waiverID: "waiver-hostile", requirementID: waivableEvidence.requirementID,
            requirementVersion: 1, evaluatedRevision: 7, reasonCode: "site_condition",
            actorReference: "actor-hostile", scopeID: "workflow-1", policySHA256: policy
        )
        let invalidWaiverInput = try self.input(
            waivableEvidence, state: .notSatisfied,
            evidence: [evidence("invalid-photo", kind: "photo", state: .invalid)],
            waiver: waiver
        )
        let invalidWaiverEvaluation = try RequirementEvaluationEngineV1.evaluate(
            invalidWaiverInput, registry: registry(for: [waivableEvidence])
        )
        XCTAssertEqual(invalidWaiverEvaluation.result, .notSatisfied)
        XCTAssertTrue(invalidWaiverEvaluation.reasonCodes.contains(.evidenceInvalid))
        XCTAssertTrue(invalidWaiverEvaluation.reasonCodes.contains(.waiverNotAllowed))
        XCTAssertFalse(invalidWaiverEvaluation.reasonCodes.contains(.waiverAccepted))

        let malformedReference = try JSONDecoder().decode(
            RequirementEvidenceReferenceV1.self,
            from: Data(#"{"referenceID":"decoded-reference","evidenceKindID":"photo","evidenceRevision":0,"state":"VALID"}"#.utf8)
        )
        XCTAssertThrowsError(try RequirementEvaluationInputV1(
            definition: required, evaluatedRevision: 7, scopeID: "workflow-1",
            responseState: .satisfied, evidenceReferences: [malformedReference]
        ))

        let malformedRegistry = try JSONDecoder().decode(
            RequirementEvaluatorRegistryV1.self,
            from: Data(#"{"rules":[{"requirementTypeID":"evidence","acceptedResponseStates":[]}] }"#.utf8)
        )
        XCTAssertThrowsError(try malformedRegistry.rule(for: "evidence"))

        let emptyDigest = try RequirementAssuranceCanonicalV1.sha256([RequirementEvaluationV1]())
        let emptyPolicyDigest = try RequirementEvaluationEngineV1.policySetSHA256([])
        let forgedDecision = try CompletionDecisionV1(
            evaluatedRevision: 7, policySetSHA256: emptyPolicyDigest,
            disposition: .permitted, hardBlockerRequirementIDs: [], warningRequirementIDs: [],
            notApplicableRequirementIDs: [], unknownRequirementIDs: [], waivedRequirementIDs: [],
            evaluationSetSHA256: emptyDigest
        )
        XCTAssertThrowsError(try RequirementAssuranceSnapshotV1(
            workflowRecordID: recordID, workspaceID: workspaceID, evaluatedRevision: 7,
            policySetSHA256: emptyPolicyDigest, evaluations: [], findings: [],
            decision: forgedDecision
        ))

        let evaluationPolicyDigest = try RequirementEvaluationEngineV1.policySetSHA256([evaluation])
        let forgedPermittedDecision = try CompletionDecisionV1(
            evaluatedRevision: 7, policySetSHA256: evaluationPolicyDigest,
            disposition: .permitted, hardBlockerRequirementIDs: [], warningRequirementIDs: [],
            notApplicableRequirementIDs: [], unknownRequirementIDs: [], waivedRequirementIDs: [],
            evaluationSetSHA256: try RequirementAssuranceCanonicalV1.sha256([evaluation])
        )
        XCTAssertThrowsError(try RequirementAssuranceSnapshotV1(
            workflowRecordID: recordID, workspaceID: workspaceID, evaluatedRevision: 7,
            policySetSHA256: evaluationPolicyDigest, evaluations: [evaluation], findings: [],
            decision: forgedPermittedDecision
        ))
    }

    func testV9_21I01InterruptedRebuildPreservesPriorAcceptedRevisionOrNoProjection() throws {
        let row = try RequirementAssuranceRow.blockingUnknownBackfill(
            workflowRecordID: recordID, workspaceID: workspaceID, evaluatedRevision: 1,
            requirementID: "backfill-required", requirementVersion: 1,
            requirementTypeID: "response", policySHA256: policy,
            mutationID: mutationID, timestamp: Date(timeIntervalSince1970: 1)
        )
        let prior = try row.snapshot()
        XCTAssertEqual(prior.decision.disposition, .blocked)
        XCTAssertThrowsError(try row.replace(
            with: prior, expectedRevision: 1,
            mutationID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
            updatedAt: Date(timeIntervalSince1970: 2)
        ))
        XCTAssertEqual(try row.snapshot(), prior)
        XCTAssertEqual(try row.currentDecision().disposition, .blocked)
    }

    func testV9_21R01CanonicalRebuildAndLifecycleRoundTripAreDeterministic() throws {
        let definition = try self.definition("required", type: "evidence", effect: .hardBlocker,
                                             requiredEvidence: ["photo"])
        let inputs = try [input(definition, state: .satisfied,
                                evidence: [evidence("photo-1", kind: "photo", state: .valid)])]
        let registry = try self.registry(for: [definition])
        let integrity = try RequirementIntegrityInputV1(
            canonicalEvidenceReferenceIDs: ["photo-1"], snapshotSHA256: nil, reportSHA256: nil
        )
        let first = try RequirementEvaluationEngineV1.makeSnapshot(
            workflowRecordID: recordID, workspaceID: workspaceID, inputs: inputs,
            registry: registry, integrity: integrity
        )
        let second = try RequirementEvaluationEngineV1.makeSnapshot(
            workflowRecordID: recordID, workspaceID: workspaceID, inputs: inputs,
            registry: registry, integrity: integrity
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(try RequirementAssuranceCanonicalV1.data(first),
                       try RequirementAssuranceCanonicalV1.data(second))
        let row = try RequirementAssuranceRow(
            snapshot: first, mutationID: mutationID,
            createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertEqual(try row.snapshot(), first)
        let value = try corpus()
        let allIDs = (value.goldenCases + value.hostileCases + value.interruptionCases + value.lifecycleCases).map(\.id)
        for evidenceID in ["V23-P03-C12-G01", "V23-P03-C12-A01", "V23-P03-C12-H01",
                           "V23-P03-C12-I01", "V23-P03-C12-R01"] {
            XCTAssertTrue(allIDs.contains(evidenceID))
        }
    }

    private func definition(
        _ id: String, type: String, effect: RequirementGateEffectV1,
        allowsNA: Bool = false, requiredEvidence: [String] = [], waiverReasons: [String] = []
    ) throws -> RequirementDefinitionV1 {
        try RequirementDefinitionV1(
            requirementID: id, requirementVersion: 1, requirementTypeID: type,
            policySHA256: policy, gateEffect: effect, allowsNotApplicable: allowsNA,
            requiredEvidenceKindIDs: requiredEvidence.sorted(),
            allowedWaiverReasonCodes: waiverReasons.sorted()
        )
    }

    private func input(
        _ definition: RequirementDefinitionV1,
        state: RequirementResponseStateV1,
        evidence: [RequirementEvidenceReferenceV1] = [], waiver: RequirementWaiverV1? = nil
    ) throws -> RequirementEvaluationInputV1 {
        try RequirementEvaluationInputV1(
            definition: definition, evaluatedRevision: 7, scopeID: "workflow-1", responseState: state,
            evidenceReferences: evidence.sorted(), waiver: waiver
        )
    }

    private func evidence(
        _ id: String, kind: String, state: RequirementEvidenceStateV1
    ) throws -> RequirementEvidenceReferenceV1 {
        try RequirementEvidenceReferenceV1(
            referenceID: id, evidenceKindID: kind, evidenceRevision: 1, state: state
        )
    }

    private func registry(for definitions: [RequirementDefinitionV1]) throws -> RequirementEvaluatorRegistryV1 {
        let types = Set(definitions.map(\.requirementTypeID)).sorted()
        return try RequirementEvaluatorRegistryV1(rules: types.map {
            try RequirementEvaluationRuleV1(
                requirementTypeID: $0,
                acceptedResponseStates: RequirementResponseStateV1.allCases.sorted { $0.rawValue < $1.rawValue }
            )
        })
    }

    private struct Corpus: Decodable {
        struct Case: Decodable { let id: String; let classification: String; let expectedResult: String; let reasonCodes: [String] }
        let schema: String; let schemaVersion: Int
        let goldenCases: [Case]; let hostileCases: [Case]
        let interruptionCases: [Case]; let lifecycleCases: [Case]
    }

    private func corpus() throws -> Corpus {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(
            forResource: "V21P03C12RequirementAssuranceCorpusV1",
            withExtension: "json", subdirectory: "Fixtures/V21/Requirements"
        ) ?? bundle.url(forResource: "V21P03C12RequirementAssuranceCorpusV1", withExtension: "json")
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: try XCTUnwrap(url)))
    }
}

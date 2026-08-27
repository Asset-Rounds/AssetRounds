import Foundation

enum RequirementEvaluationEngineV1 {
    static func evaluate(
        _ input: RequirementEvaluationInputV1,
        registry: RequirementEvaluatorRegistryV1
    ) throws -> RequirementEvaluationV1 {
        try input.validate()
        let rule = try registry.rule(for: input.definition.requirementTypeID)
        let referenceIDs = input.evidenceReferences.map(\.referenceID).sorted()
        let duplicateIDs = duplicateValues(referenceIDs)
        let invalid = input.evidenceReferences.filter { $0.state == .invalid }.map(\.referenceID).sorted()
        let validKinds = Set(input.evidenceReferences.filter { $0.state == .valid }.map(\.evidenceKindID))
        let invalidKinds = Set(input.evidenceReferences.filter { $0.state == .invalid }.map(\.evidenceKindID))
        let missing = input.definition.requiredEvidenceKindIDs.filter { !validKinds.contains($0) }
        let contradictory = !validKinds.intersection(invalidKinds).isEmpty

        var result: RequirementEvaluationResultV1
        var reasons: Set<RequirementReasonCodeV1> = []
        switch input.responseState {
        case .satisfied:
            result = .satisfied; reasons.insert(.satisfied)
        case .notSatisfied:
            result = .notSatisfied; reasons.insert(.responseNotSatisfied)
        case .notApplicable:
            if input.definition.allowsNotApplicable {
                result = .notApplicable; reasons.insert(.notApplicableAccepted)
            } else {
                result = .notSatisfied; reasons.insert(.notApplicableNotAllowed)
            }
        case .unknown:
            result = .unknown; reasons.insert(.unknownResponse)
        case .unanswered:
            result = .unknown; reasons.insert(.unansweredRequirement)
        }
        if !rule.acceptedResponseStates.contains(input.responseState) {
            result = .unknown; reasons.insert(.unknownResponse)
        }
        if !missing.isEmpty { result = .notSatisfied; reasons.insert(.requiredEvidenceMissing) }
        if !invalid.isEmpty { result = .notSatisfied; reasons.insert(.evidenceInvalid) }
        if !duplicateIDs.isEmpty { result = .notSatisfied; reasons.insert(.evidenceDuplicated) }
        if contradictory { result = .notSatisfied; reasons.insert(.evidenceContradictory) }
        let hasEvidenceFailure = !missing.isEmpty || !invalid.isEmpty
            || !duplicateIDs.isEmpty || contradictory

        var waiverID: String?
        if let waiver = input.waiver {
            let waiverReason = try validateWaiver(waiver, input: input)
            if hasEvidenceFailure {
                reasons.insert(.waiverNotAllowed)
            } else if waiverReason == nil {
                result = .waived; reasons = [.waiverAccepted]; waiverID = waiver.waiverID
            } else {
                reasons.insert(waiverReason!)
            }
        }
        return try RequirementEvaluationV1(
            definition: input.definition,
            evaluatedRevision: input.evaluatedRevision,
            result: result,
            reasonCodes: reasons.sorted(),
            missingEvidenceReferences: missing.sorted(),
            invalidEvidenceReferences: Array(Set(invalid + duplicateIDs)).sorted(),
            evidenceReferenceIDs: Array(Set(referenceIDs)).sorted(),
            waiverID: waiverID
        )
    }

    static func evaluateAll(
        _ inputs: [RequirementEvaluationInputV1],
        registry: RequirementEvaluatorRegistryV1
    ) throws -> [RequirementEvaluationV1] {
        guard !inputs.isEmpty, inputs.count <= RequirementAssuranceLimitsV1.maximumRequirements,
              Set(inputs.map { $0.definition.requirementID }).count == inputs.count,
              Set(inputs.map(\.evaluatedRevision)).count == 1 else {
            throw RequirementAssuranceFailureV1.invalidValue
        }
        try registry.validateCoverage(of: inputs.map(\.definition))
        return try inputs.map { try evaluate($0, registry: registry) }.sorted()
    }

    static func completionDecision(
        evaluations: [RequirementEvaluationV1]
    ) throws -> CompletionDecisionV1 {
        guard !evaluations.isEmpty, evaluations == evaluations.sorted(),
              Set(evaluations.map(\.requirementID)).count == evaluations.count,
              let revision = evaluations.first?.evaluatedRevision,
              evaluations.allSatisfy({ $0.evaluatedRevision == revision }) else {
            throw RequirementAssuranceFailureV1.invalidValue
        }
        try evaluations.forEach { try $0.validate() }
        let unknown = evaluations.filter { $0.result == .unknown }.map(\.requirementID).sorted()
        let hard = evaluations.filter {
            $0.gateEffect == .hardBlocker && [.notSatisfied, .unknown].contains($0.result)
        }.map(\.requirementID).sorted()
        let warnings = evaluations.filter {
            $0.gateEffect == .warning && $0.result == .notSatisfied
        }.map(\.requirementID).sorted()
        return try CompletionDecisionV1(
            evaluatedRevision: revision,
            policySetSHA256: try policySetSHA256(evaluations),
            disposition: hard.isEmpty && unknown.isEmpty ? .permitted : .blocked,
            hardBlockerRequirementIDs: hard,
            warningRequirementIDs: warnings,
            notApplicableRequirementIDs: evaluations.filter { $0.result == .notApplicable }.map(\.requirementID).sorted(),
            unknownRequirementIDs: unknown,
            waivedRequirementIDs: evaluations.filter { $0.result == .waived }.map(\.requirementID).sorted(),
            evaluationSetSHA256: try RequirementAssuranceCanonicalV1.sha256(evaluations)
        )
    }

    static func policySetSHA256(_ evaluations: [RequirementEvaluationV1]) throws -> String {
        struct Binding: Codable { let requirementID: String; let policySHA256: String }
        return try RequirementAssuranceCanonicalV1.sha256(
            evaluations.sorted().map { Binding(requirementID: $0.requirementID, policySHA256: $0.policySHA256) }
        )
    }

    static func lint(
        inputs: [RequirementEvaluationInputV1],
        evaluations: [RequirementEvaluationV1],
        integrity: RequirementIntegrityInputV1
    ) throws -> [IntegrityFindingV1] {
        let evaluationByID = Dictionary(uniqueKeysWithValues: evaluations.map { ($0.requirementID, $0) })
        let referenced = inputs.flatMap(\.evidenceReferences).map(\.referenceID)
        var findings: [IntegrityFindingV1] = []
        for input in inputs.sorted(by: { $0.definition.requirementID < $1.definition.requirementID }) {
            let id = input.definition.requirementID
            guard let evaluation = evaluationByID[id] else {
                findings.append(try .init(kind: .invalidState, requirementID: id,
                                          reasonCode: "evaluation_missing")); continue
            }
            if evaluation.requirementVersion != input.definition.requirementVersion
                || evaluation.requirementTypeID != input.definition.requirementTypeID
                || evaluation.evaluatedRevision != input.evaluatedRevision
                || evaluation.policySHA256 != input.definition.policySHA256 {
                findings.append(try .init(kind: .invalidState, requirementID: id,
                                          reasonCode: "stale_evaluation_binding"))
            }
            if input.responseState == .unanswered {
                findings.append(try .init(kind: .unansweredRequirement, requirementID: id,
                                          reasonCode: "unanswered_requirement"))
            }
            if !evaluation.missingEvidenceReferences.isEmpty {
                findings.append(try .init(kind: .missingRequiredEvidence, requirementID: id,
                                          referenceIDs: evaluation.missingEvidenceReferences,
                                          reasonCode: "required_evidence_missing"))
            }
            let invalidReferences = input.evidenceReferences
                .filter { $0.state == .invalid }.map(\.referenceID)
            let canonicalInvalidReferences = Array(Set(invalidReferences)).sorted()
            if !canonicalInvalidReferences.isEmpty {
                findings.append(try .init(kind: .invalidState, requirementID: id,
                                          referenceIDs: canonicalInvalidReferences,
                                          reasonCode: "evidence_invalid"))
            }
            let duplicates = duplicateValues(input.evidenceReferences.map(\.referenceID).sorted())
            if !duplicates.isEmpty {
                findings.append(try .init(kind: .duplicateEvidenceReference, requirementID: id,
                                          referenceIDs: duplicates, reasonCode: "evidence_duplicated"))
            }
            let statesByKind = Dictionary(grouping: input.evidenceReferences, by: \.evidenceKindID)
            let contradictory = statesByKind.filter { Set($0.value.map(\.state)).count > 1 }
                .flatMap { $0.value.map(\.referenceID) }.sorted()
            if !contradictory.isEmpty {
                findings.append(try .init(kind: .contradictoryEvidence, requirementID: id,
                                          referenceIDs: contradictory, reasonCode: "evidence_contradictory"))
            }
        }
        let canonical = Set(integrity.canonicalEvidenceReferenceIDs)
        let orphans = canonical.subtracting(referenced).sorted()
        if !orphans.isEmpty {
            findings.append(try .init(kind: .orphanEvidenceReference,
                                      referenceIDs: orphans, reasonCode: "orphan_evidence_reference"))
        }
        let missingCanonicalReferences = Set(referenced).subtracting(canonical).sorted()
        if !missingCanonicalReferences.isEmpty {
            findings.append(try .init(kind: .invalidState,
                                      referenceIDs: missingCanonicalReferences,
                                      reasonCode: "unknown_evidence_reference"))
        }
        if let snapshot = integrity.snapshotSHA256, let report = integrity.reportSHA256,
           snapshot != report {
            findings.append(try .init(kind: .snapshotReportDivergence,
                                      referenceIDs: [], reasonCode: "snapshot_report_divergence"))
        }
        return findings.sorted()
    }

    static func makeSnapshot(
        workflowRecordID: UUID,
        workspaceID: UUID,
        inputs: [RequirementEvaluationInputV1],
        registry: RequirementEvaluatorRegistryV1,
        integrity: RequirementIntegrityInputV1
    ) throws -> RequirementAssuranceSnapshotV1 {
        let evaluations = try evaluateAll(inputs, registry: registry)
        let decision = try completionDecision(evaluations: evaluations)
        let findings = try lint(inputs: inputs, evaluations: evaluations, integrity: integrity)
        return try RequirementAssuranceSnapshotV1(
            workflowRecordID: workflowRecordID, workspaceID: workspaceID,
            evaluatedRevision: decision.evaluatedRevision,
            policySetSHA256: decision.policySetSHA256,
            evaluations: evaluations, findings: findings, decision: decision
        )
    }

    private static func validateWaiver(
        _ waiver: RequirementWaiverV1,
        input: RequirementEvaluationInputV1
    ) throws -> RequirementReasonCodeV1? {
        try waiver.validate()
        guard input.responseState != .satisfied,
              input.responseState != .notApplicable else { return .waiverNotAllowed }
        guard !input.definition.allowedWaiverReasonCodes.isEmpty else { return .waiverNotAllowed }
        guard input.definition.allowedWaiverReasonCodes.contains(waiver.reasonCode) else { return .waiverReasonNotAllowed }
        guard waiver.requirementID == input.definition.requirementID,
              waiver.requirementVersion == input.definition.requirementVersion,
              waiver.scopeID == input.scopeID,
              waiver.policySHA256 == input.definition.policySHA256 else { return .waiverScopeMismatch }
        guard waiver.evaluatedRevision == input.evaluatedRevision else { return .waiverRevisionMismatch }
        return nil
    }

    private static func duplicateValues(_ sorted: [String]) -> [String] {
        guard sorted.count > 1 else { return [] }
        return Array(Set(zip(sorted, sorted.dropFirst()).compactMap { pair in
            pair.0 == pair.1 ? pair.0 : nil
        })).sorted()
    }
}

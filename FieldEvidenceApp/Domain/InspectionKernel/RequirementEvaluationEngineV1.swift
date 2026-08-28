import Foundation

enum RequirementEvaluationEngineV1 {
    static func assurancePreview(
        previewID: UUID,
        workspaceID: WorkspaceID,
        audience: EvidenceAudienceV1,
        snapshotSHA256: String,
        projectionVersion: String,
        evaluations: [RequirementEvaluationV1],
        links: [ClaimEvidenceLinkV1],
        createdAt: Date
    ) throws -> AssuranceProjectionPreviewV1 {
        try evaluations.forEach { try $0.validate() }
        try links.forEach { try $0.validate() }
        let claims = Set(evaluations.map(\.assuranceClaimID))
        guard Set(evaluations.map(\.requirementID)).count == evaluations.count,
              links.allSatisfy({ link in
                  claims.contains(link.claimID)
                      && evaluations.contains(where: { $0.requirementID == link.criterionID })
              }) else {
            throw EvidenceAssuranceFailureV1.invalidValue
        }
        return try AssuranceProjectionPreviewV1(
            previewID: previewID,
            workspaceID: workspaceID,
            audience: audience,
            snapshotSHA256: snapshotSHA256,
            projectionVersion: projectionVersion,
            links: links,
            createdAt: createdAt
        )
    }

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
            } else if let waiverReason {
                reasons.insert(waiverReason)
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

extension RequirementEvaluationEngineV1 {
    static func validateInspectionReviewEvidence(
        _ reference: ReviewEvidenceReferenceV1,
        evaluation: RequirementEvaluationV1
    ) throws {
        let expected = try evaluation.inspectionReviewEvidenceReference()
        guard reference == expected else { throw RequirementAssuranceFailureV1.invalidEvidence }
    }

    /// Keeps C19 quality review out of automatic compliance conclusions. A
    /// requirement engine can still evaluate explicit requirement evidence
    /// through `evaluate`; this helper is only the typed quality boundary.
    static func c19MeasurementQualityResult(
        for assessment: MeasurementQualityAssessmentV1
    ) throws -> RequirementEvaluationResultV1 {
        try MeasurementIntegrityRequirementProjectionV1.result(for: assessment)
    }

    /// Checks an explicit C20 derivative evidence reference before ordinary
    /// requirement evaluation. This is intentionally a validation-only seam:
    /// it never converts privacy review state into an automatic requirement or
    /// compliance result.
    static func c20ValidateReviewedDerivativeEvidence(
        _ input: RequirementEvaluationInputV1,
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        at now: Date
    ) throws -> ContentReferenceV1 {
        try input.c20ValidateReviewedDerivative(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            at: now
        )
    }
}

/// The closed, app-bundled evaluator registry for C40. Package declarations may
/// bind these identities, versions, and digests, but never provide executable
/// formulas or scripts.
enum BundledDerivedFactEvaluatorRegistryV1 {
    static let evaluatorVersion = "1"

    static func evaluatorID(for kind: DerivedFactEvaluatorKindV1) -> String {
        switch kind {
        case .identityCanonical: return "com.assetrounds.derived.identity"
        case .arithmeticMeanCanonical: return "com.assetrounds.derived.arithmetic-mean"
        case .ratioPercent: return "com.assetrounds.derived.ratio-percent"
        }
    }

    static func implementationSHA256(for kind: DerivedFactEvaluatorKindV1) throws -> String {
        struct DigestBasis: Codable {
            let evaluatorID: String
            let evaluatorVersion: String
            let kind: DerivedFactEvaluatorKindV1
            let arithmeticPolicy: String
        }
        return try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            evaluatorID: evaluatorID(for: kind),
            evaluatorVersion: evaluatorVersion,
            kind: kind,
            arithmeticPolicy: "CHECKED_INT64_EXACT_DECIMAL_TIES_TO_EVEN_V1"
        ))
    }

    static func descriptor(
        descriptorID: UUID,
        workspaceID: WorkspaceID,
        kind: DerivedFactEvaluatorKindV1,
        inputDimension: MeasurementDimensionV1,
        supersedesDescriptorID: UUID? = nil,
        recordedAt: Date
    ) throws -> DerivedFactEvaluatorDescriptorV1 {
        try DerivedFactEvaluatorDescriptorV1(
            descriptorID: descriptorID,
            workspaceID: workspaceID,
            evaluatorID: evaluatorID(for: kind),
            evaluatorVersion: evaluatorVersion,
            implementationSHA256: implementationSHA256(for: kind),
            kind: kind,
            inputDimension: inputDimension,
            outputDimension: kind == .ratioPercent ? .dimensionless : inputDimension,
            supersedesDescriptorID: supersedesDescriptorID,
            recordedAt: recordedAt
        )
    }

    static func validate(_ descriptor: DerivedFactEvaluatorDescriptorV1) throws {
        try descriptor.validate()
        guard descriptor.evaluatorID == evaluatorID(for: descriptor.kind),
              descriptor.evaluatorVersion == evaluatorVersion,
              descriptor.implementationSHA256 == (try implementationSHA256(for: descriptor.kind)),
              descriptor.outputDimension == (descriptor.kind == .ratioPercent
                ? .dimensionless : descriptor.inputDimension) else {
            throw AuthorityCriterionFailureV1.unsupportedEvaluator
        }
    }
}

/// Pure deterministic C40 derivation. It consumes C03 canonical measurements
/// and emits one immutable provenance value; it performs no persistence.
enum DeterministicDerivedFactEvaluatorV1 {
    private struct MeasuredInputV1 {
        let source: DerivedFactInputV1
        let measurement: ExactMeasurementV1
    }

    static func evaluate(
        provenanceID: UUID,
        workspaceID: WorkspaceID,
        protocolRelease: MeasurementProtocolReleaseV1,
        evaluator: DerivedFactEvaluatorDescriptorV1,
        inputs: [DerivedFactInputV1],
        predecessorProvenanceID: UUID? = nil,
        recordedAt: Date
    ) throws -> DerivedFactProvenanceV1 {
        try protocolRelease.validate()
        try BundledDerivedFactEvaluatorRegistryV1.validate(evaluator)
        guard protocolRelease.workspaceID == workspaceID,
              evaluator.workspaceID == workspaceID,
              protocolRelease.evaluatorDescriptorID == evaluator.descriptorID,
              protocolRelease.dimension == evaluator.inputDimension else {
            throw AuthorityCriterionFailureV1.wrongWorkspace
        }

        let ordered = inputs.sorted {
            if $0.sampleOrdinal != $1.sampleOrdinal {
                return $0.sampleOrdinal < $1.sampleOrdinal
            }
            return $0.sampleID.uuidString < $1.sampleID.uuidString
        }
        try ordered.forEach { try $0.validate() }
        guard Set(ordered.map(\.sampleID)).count == ordered.count,
              Set(ordered.map(\.sampleOrdinal)).count == ordered.count else {
            throw AuthorityCriterionFailureV1.duplicateSample
        }
        let expectedOrdinals = ordered.indices.map { $0 + 1 }
        guard ordered.map(\.sampleOrdinal) == expectedOrdinals else {
            throw AuthorityCriterionFailureV1.invalidValue
        }
        guard ordered.count <= protocolRelease.maximumSampleCount else {
            throw AuthorityCriterionFailureV1.invalidValue
        }

        var measured: [MeasuredInputV1] = []
        var hasMissingSample = false
        for input in ordered {
            switch input.state {
            case .missing:
                guard input.measurement == nil else {
                    throw AuthorityCriterionFailureV1.invalidValue
                }
                hasMissingSample = true
            case .present:
                guard let measurement = input.measurement else {
                    throw AuthorityCriterionFailureV1.invalidValue
                }
                try validate(
                    measurement: measurement,
                    protocolRelease: protocolRelease,
                    evaluator: evaluator
                )
                measured.append(.init(source: input, measurement: measurement))
            case .outlier:
                guard let measurement = input.measurement else {
                    throw AuthorityCriterionFailureV1.invalidValue
                }
                try validate(
                    measurement: measurement,
                    protocolRelease: protocolRelease,
                    evaluator: evaluator
                )
                guard protocolRelease.outlierPolicy == .retainAll else {
                    throw AuthorityCriterionFailureV1.invalidValue
                }
                measured.append(.init(source: input, measurement: measurement))
            }
        }

        if hasMissingSample {
            if protocolRelease.missingSamplePolicy == .inconclusive {
                return try DerivedFactProvenanceV1(
                    provenanceID: provenanceID, workspaceID: workspaceID,
                    protocolReleaseID: protocolRelease.releaseID,
                    evaluatorDescriptorID: evaluator.descriptorID, inputs: ordered,
                    result: nil, disposition: .inconclusive,
                    predecessorProvenanceID: predecessorProvenanceID, recordedAt: recordedAt
                )
            }
            throw AuthorityCriterionFailureV1.insufficientSamples
        }
        guard measured.count >= protocolRelease.minimumSampleCount else {
            if protocolRelease.missingSamplePolicy == .inconclusive {
                return try DerivedFactProvenanceV1(
                    provenanceID: provenanceID, workspaceID: workspaceID,
                    protocolReleaseID: protocolRelease.releaseID,
                    evaluatorDescriptorID: evaluator.descriptorID, inputs: ordered,
                    result: nil, disposition: .inconclusive,
                    predecessorProvenanceID: predecessorProvenanceID, recordedAt: recordedAt
                )
            }
            throw AuthorityCriterionFailureV1.insufficientSamples
        }
        if protocolRelease.duplicatePolicy == .reject {
            let canonicalSamples = measured.map {
                "\($0.measurement.canonicalValue.mantissa):\($0.measurement.canonicalValue.scale):\($0.measurement.canonicalUnitID)"
            }
            guard Set(canonicalSamples).count == canonicalSamples.count else {
                throw AuthorityCriterionFailureV1.duplicateSample
            }
        }

        do {
            let result = try resultMeasurement(
                kind: evaluator.kind,
                evaluatorID: evaluator.evaluatorID,
                inputs: measured
            )
            return try DerivedFactProvenanceV1(
                provenanceID: provenanceID,
                workspaceID: workspaceID,
                protocolReleaseID: protocolRelease.releaseID,
                evaluatorDescriptorID: evaluator.descriptorID,
                inputs: ordered,
                result: result,
                disposition: .evaluated,
                uncertaintyCanonical: try maximumUncertainty(in: measured),
                predecessorProvenanceID: predecessorProvenanceID,
                recordedAt: recordedAt
            )
        } catch is ResponseContractFailureV1 {
            throw AuthorityCriterionFailureV1.arithmeticFailure
        }
    }

    private static func resultMeasurement(
        kind: DerivedFactEvaluatorKindV1,
        evaluatorID: String,
        inputs: [MeasuredInputV1]
    ) throws -> ExactMeasurementV1 {
        guard let first = inputs.first else { throw AuthorityCriterionFailureV1.insufficientSamples }
        let value: ExactDecimalV1
        let unitID: String
        switch kind {
        case .identityCanonical:
            guard inputs.count == 1 else { throw AuthorityCriterionFailureV1.invalidValue }
            value = first.measurement.canonicalValue
            unitID = first.measurement.canonicalUnitID
        case .arithmeticMeanCanonical:
            let targetScale = inputs.map { $0.measurement.canonicalValue.scale }.max() ?? 0
            var sum: Int64 = 0
            for input in inputs {
                sum = try ExactIntegerMathV1.add(
                    sum,
                    input.measurement.canonicalValue.rescaledExactly(to: targetScale).mantissa
                )
            }
            let rounded = try ExactUnitConverterV1.rounded(
                numerator: sum,
                denominator: Int64(inputs.count),
                targetScale: targetScale
            )
            value = rounded.canonicalValue
            unitID = first.measurement.canonicalUnitID
        case .ratioPercent:
            guard inputs.count == 2 else { throw AuthorityCriterionFailureV1.invalidValue }
            let lhs = inputs[0].measurement.canonicalValue
            let rhs = inputs[1].measurement.canonicalValue
            guard rhs.mantissa != 0 else { throw AuthorityCriterionFailureV1.arithmeticFailure }
            var numerator = try ExactIntegerMathV1.multiply(
                lhs.mantissa, ExactIntegerMathV1.powerOfTen(rhs.scale)
            )
            numerator = try ExactIntegerMathV1.multiply(numerator, 100)
            var denominator = try ExactIntegerMathV1.multiply(
                rhs.mantissa, ExactIntegerMathV1.powerOfTen(lhs.scale)
            )
            if denominator < 0 {
                numerator = try ExactIntegerMathV1.multiply(numerator, -1)
                denominator = try ExactIntegerMathV1.multiply(denominator, -1)
            }
            value = try ExactUnitConverterV1.rounded(
                numerator: numerator, denominator: denominator, targetScale: 9
            ).canonicalValue
            unitID = "1"
        }
        return try ExactMeasurementV1(
            enteredValue: value,
            enteredUnitID: unitID,
            precisionScale: value.scale,
            uncertaintyCanonical: nil,
            source: .derived,
            captureMethodID: evaluatorID
        )
    }

    private static func maximumUncertainty(
        in inputs: [MeasuredInputV1]
    ) throws -> ExactDecimalV1? {
        var maximum: ExactDecimalV1?
        for value in inputs.compactMap({ $0.measurement.uncertaintyCanonical }) {
            if let existing = maximum {
                if try existing.compared(to: value) == .orderedAscending { maximum = value }
            } else {
                maximum = value
            }
        }
        return maximum
    }

    private static func validate(
        measurement: ExactMeasurementV1,
        protocolRelease: MeasurementProtocolReleaseV1,
        evaluator: DerivedFactEvaluatorDescriptorV1
    ) throws {
        try measurement.validate()
        guard measurement.dimension == protocolRelease.dimension,
              measurement.dimension == evaluator.inputDimension else {
            throw AuthorityCriterionFailureV1.dimensionMismatch
        }
        if protocolRelease.requiresUncertainty,
           measurement.uncertaintyCanonical == nil {
            throw AuthorityCriterionFailureV1.invalidValue
        }
    }
}

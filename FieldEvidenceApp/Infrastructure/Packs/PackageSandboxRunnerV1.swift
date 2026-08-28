import Foundation

protocol PackageSandboxCheckExecutingV1: Sendable {
    func execute(
        kind: PackageSandboxCheckKindV1,
        fixtureID: String,
        fixtureSHA256: String,
        release: InspectionPackageReleaseV1,
        semanticDiff: PackageSemanticDiffV1
    ) async throws -> PackageSandboxExecutionOutcomeV1
}

extension PackageSandboxRunnerV1 {
    func validateFieldReferences(_ closures: [FieldReferenceLifecycleClosureV1], checkedAt: Date) throws {
        for closure in closures {
            let readiness = try closure.validate(checkedAt: checkedAt)
            guard readiness.availability == .readyOffline else { throw FieldReferencePackFailureV1.missingContent }
        }
    }
}

extension PackageSandboxRunnerV1 {
    func run(
        runID: UUID,
        workspaceID: WorkspaceID,
        release: InspectionPackageReleaseV1,
        semanticDiff: PackageSemanticDiffV1,
        exactHead: String,
        fixtures: PackageSandboxFixtureMatrixV1,
        mutationID: MutationIDV1,
        admittedBy closure: ClientCapabilityLifecycleClosureV1
    ) async throws -> PackageSandboxRunV1 {
        try closure.validate()
        guard closure.profile.workspaceID == workspaceID,
              closure.release.packageReleaseID == release.packageReleaseID,
              closure.release.packageSHA256 == release.packageSHA256,
              closure.release.workflowSHA256 == release.workflowSHA256,
              closure.decision.operation == .upgradeDraft,
              closure.decision.admission == .readWrite else {
            throw PackageEvolutionFailureV1.incompatiblePromotion
        }
        return try await run(runID: runID, workspaceID: workspaceID, release: release,
                             semanticDiff: semanticDiff, exactHead: exactHead,
                             fixtures: fixtures, mutationID: mutationID)
    }
}

protocol PackageSandboxShapeCheckExecutingV1: PackageSandboxCheckExecutingV1 {
    func execute(
        kind: PackageSandboxCheckKindV1,
        shape: PackageSandboxFixtureShapeV1,
        fixtureID: String,
        fixtureSHA256: String,
        release: InspectionPackageReleaseV1,
        semanticDiff: PackageSemanticDiffV1
    ) async throws -> PackageSandboxExecutionOutcomeV1
}

/// Production C18 sandbox consumer. This type is intentionally incapable of
/// writing or activating a package: its inputs are immutable release/diff
/// values, and every branch calls the existing read-only canonical consumer.
struct CanonicalPackageSandboxConsumerExecutorV1: PackageSandboxShapeCheckExecutingV1 {
    /// Shape-less execution is deliberately unavailable for the canonical
    /// executor; production composition always dispatches the typed shape API.
    func execute(
        kind: PackageSandboxCheckKindV1,
        fixtureID: String,
        fixtureSHA256: String,
        release: InspectionPackageReleaseV1,
        semanticDiff: PackageSemanticDiffV1
    ) async throws -> PackageSandboxExecutionOutcomeV1 {
        throw PackageEvolutionFailureV1.incompleteSandbox
    }

    func execute(
        kind: PackageSandboxCheckKindV1,
        shape: PackageSandboxFixtureShapeV1,
        fixtureID: String,
        fixtureSHA256: String,
        release: InspectionPackageReleaseV1,
        semanticDiff: PackageSemanticDiffV1
    ) async throws -> PackageSandboxExecutionOutcomeV1 {
        try release.validate(); try semanticDiff.validate()
        guard release.packageReleaseID == semanticDiff.target.packageReleaseID,
              KernelCanonicalHashV1.validSHA256(fixtureSHA256) else {
            throw PackageEvolutionFailureV1.incompleteSandbox
        }
        let package = try InspectionPackageCanonicalCodecV2.decode(release.canonicalPackageBytes)
        let workflow = try WorkflowDefinitionCanonicalCodecV1.decode(release.canonicalWorkflowBytes)
        let metadata = try PackageEvolutionConsumerMetadataV1(
            packageID: release.packageID,
            packageReleaseID: release.packageReleaseID,
            semanticClassification: semanticDiff.classification,
            promotionStatus: shape == .minimal ? .preview : .forwardFixRequired,
            sandboxDisposition: .completePass,
            localizationReleaseSHA256: semanticDiff.target.semanticReleaseBindings.localizationReleaseSHA256
        )
        var evidence: [String] = [
            kind.rawValue, shape.rawValue, fixtureID, fixtureSHA256,
            release.packageReleaseID, semanticDiff.diffSHA256,
        ]
        switch kind {
        case .schema:
            try InspectionPackageCompatibilityValidatorV2.validate(package)
            guard try InspectionPackageCanonicalCodecV2.encode(package) == release.canonicalPackageBytes,
                  try WorkflowDefinitionCanonicalCodecV1.encode(workflow) == release.canonicalWorkflowBytes else {
                throw PackageEvolutionFailureV1.nonCanonicalData
            }
            evidence += [release.packageSHA256, release.workflowSHA256]
        case .graph:
            _ = try WorkflowGraphValidatorV1.validate(workflow)
            let graph = try PackageSemanticGraphV1(
                release: release,
                semanticReleaseBindings: semanticDiff.target.semanticReleaseBindings
            )
            guard graph == semanticDiff.target else { throw PackageEvolutionFailureV1.incompatiblePromotion }
            evidence.append(graph.semanticGraphSHA256)
        case .localizedDisplay:
            let keyIDs = localizationKeyIDs(package)
            guard !keyIDs.isEmpty, PackageEvolutionAccessibilityPolicyV1.validate() else {
                throw PackageEvolutionFailureV1.incompleteSandbox
            }
            let binding = try BundledLocalizationCatalogV1.packageEvolutionLocalizationBinding(
                metadata, keyIDs: keyIDs
            )
            try binding.validate()
            let labels = [
                BundledLocalizationCatalogV1.packageEvolutionDisplayLabel(for: metadata.promotionStatus),
                BundledLocalizationCatalogV1.packageEvolutionDisplayLabel(for: metadata.semanticClassification),
            ]
            guard labels.allSatisfy({ !$0.isEmpty }) else { throw PackageEvolutionFailureV1.incompleteSandbox }
            evidence += [try digest(binding), KernelCanonicalHashV1.sha256(Data(labels.joined(separator: "|").utf8))]
        case .reportPDF:
            let report = try PackageEvolutionReportProjectionV1(metadata: metadata, release: release)
            let data = try DeterministicPDFRendererV1.packageEvolutionMetadataData(report)
            guard try DeterministicPDFRendererV1.reopenPackageEvolutionMetadata(data) == report else {
                throw PackageEvolutionFailureV1.nonCanonicalData
            }
            evidence.append(KernelCanonicalHashV1.sha256(data))
        case .openJSON:
            let report = try PackageEvolutionReportProjectionV1(metadata: metadata, release: release)
            let output = try DeterministicOpenJSONRendererV1.renderPackageEvolution(report)
            guard try DeterministicOpenJSONRendererV1.reopenPackageEvolution(output.data) == report else {
                throw PackageEvolutionFailureV1.nonCanonicalData
            }
            evidence += [output.sha256, output.semanticSHA256]
        case .backupRestore:
            try KernelBackupRestoreRegistryV4.validatePackageEvolutionLifecycle()
            try V17PackageEvolutionImportBoundaryV1.validate(persistent: 17, records: 16)
            let releaseData = try PackageEvolutionCanonicalCodecV1.encode(release)
            let diffData = try PackageEvolutionCanonicalCodecV1.encode(semanticDiff)
            guard try PackageEvolutionCanonicalCodecV1.decode(InspectionPackageReleaseV1.self, from: releaseData) == release,
                  try PackageEvolutionCanonicalCodecV1.decode(PackageSemanticDiffV1.self, from: diffData) == semanticDiff else {
                throw PackageEvolutionFailureV1.nonCanonicalData
            }
            evidence += [KernelCanonicalHashV1.sha256(releaseData), KernelCanonicalHashV1.sha256(diffData),
                         try KernelBackupRestoreRegistryV4.canonicalDigest]
        case .deleteErase:
            try KernelDeletionEraseRegistryV4.validatePackageEvolutionLifecycle()
            try WholeSignDeletionRule.validatePackageEvolutionLifecycle(
                authority: .ordinaryAssetOrSiteDelete, before: .empty, after: .empty
            )
            try WholeSignDeletionRule.validatePackageEvolutionLifecycle(
                authority: .workspaceErase, before: .empty, after: .empty
            )
            guard PackageEvolutionEraseBoundaryV1.atomicFamilyCount == 4,
                  PackageEvolutionEraseBoundaryV1.ordinaryDeletionPreservesPromotedHistory,
                  PackageEvolutionEraseBoundaryV1.workspaceEraseClearsEntireClosure else {
                throw PackageEvolutionFailureV1.incompleteSandbox
            }
            evidence.append(try KernelDeletionEraseRegistryV4.canonicalDigest)
        case .export:
            try PackageEvolutionCompatibilityV1.current.validate()
            try PackageEvolutionCompatibilityV1.current.validateWriterVersion(
                PackageEvolutionCompatibilityV1.currentWriterVersion
            )
            evidence += [try digest(release), try digest(semanticDiff), try digest(PackageEvolutionCompatibilityV1.current)]
        case .searchRebuild:
            let record = try LocalSearchIndexStoreV1.packageEvolutionRecord(metadata: metadata)
            try LocalSearchIndexStoreV1.validatePackageEvolutionRecord(record)
            let policy = PackageEvolutionSearchPersistencePolicyV1()
            try policy.validate()
            evidence += [try digest(record), try digest(policy)]
        case .replay:
            let limits = try IntegrationEventLimitsV1()
            let registry = try IntegrationContractRegistryV1(
                releaseID: "package-evolution-sandbox-v1",
                definitions: PackageEvolutionIntegrationContractV1.definitions(),
                limits: limits
            )
            try PackageEvolutionIntegrationContractV1.validate(registry: registry)
            evidence.append(registry.registrySHA256)
        case .classification:
            let rebuilt = try PackageSemanticDifferV1.changes(
                source: semanticDiff.source, target: semanticDiff.target
            )
            guard rebuilt == semanticDiff.changes,
                  PackageSemanticDifferV1.classification(
                    source: semanticDiff.source, target: semanticDiff.target, changes: rebuilt
                  ) == semanticDiff.classification else {
                throw PackageEvolutionFailureV1.incompatiblePromotion
            }
            evidence.append(try digest(rebuilt))
        case .brandStateFixtures:
            guard BundledLocalizationCatalogV1.packageEvolutionBrandStateValues.contains(
                metadata.promotionStatus.rawValue
            ), PackageEvolutionAccessibilityPolicyV1.validate() else {
                throw PackageEvolutionFailureV1.incompleteSandbox
            }
            let label = BundledLocalizationCatalogV1.packageEvolutionBrandStateDisplayLabel(
                for: metadata.promotionStatus.rawValue
            )
            guard !label.isEmpty, label != "Unavailable" else {
                throw PackageEvolutionFailureV1.incompleteSandbox
            }
            evidence += [KernelCanonicalHashV1.sha256(Data(label.utf8)), try digest(BundledLocalizationCatalogV1.packageEvolutionAccessibilityContracts())]
        }
        return try PackageSandboxExecutionOutcomeV1(
            resultSHA256: KernelCanonicalHashV1.sha256(
                try PackageEvolutionCanonicalCodecV1.encode(evidence)
            ),
            disposition: .passed,
            activationEvidence: .notAttempted
        )
    }

    private func digest<T: Codable>(_ value: T) throws -> String {
        KernelCanonicalHashV1.sha256(try PackageEvolutionCanonicalCodecV1.encode(value))
    }

    private func localizationKeyIDs(_ package: InspectionPackageV2) -> [String] {
        Array(Set(
            package.advisoryGuidance.map(\.localizationKey)
                + package.presentation.evidencePurposes.map(\.key)
                + package.presentation.acknowledgements.map(\.key)
                + package.presentation.issueLabels.map(\.key)
                + package.presentation.couldNotVerifyReasons.map(\.key)
                + package.presentation.stageDisplays.map(\.key)
                + package.presentation.outcomeDisplays.map(\.key)
        )).sorted()
    }
}

/// Read-only observation of canonical active-pointer state. Implementations
/// return a canonical SHA even when no pointer exists (for example, the hash of
/// a typed NONE marker), so before/after nonactivation evidence is never absent.
protocol PackageSandboxActivationObservingV1: Sendable {
    func activePointerStateSHA256(workspaceID: WorkspaceID, packageID: String) async throws -> String
}

struct PackageSandboxExecutionOutcomeV1: Equatable, Sendable {
    let resultSHA256: String
    let disposition: PackageSandboxCheckDispositionV1
    let activationEvidence: PackageSandboxActivationEvidenceV1
    init(resultSHA256: String,
         disposition: PackageSandboxCheckDispositionV1,
         activationEvidence: PackageSandboxActivationEvidenceV1) throws {
        guard KernelCanonicalHashV1.validSHA256(resultSHA256) else {
            throw PackageEvolutionFailureV1.invalidDigest
        }
        self.resultSHA256 = resultSHA256; self.disposition = disposition
        self.activationEvidence = activationEvidence
    }
}

struct PackageSandboxFixtureV1: Codable, Equatable, Sendable {
    let fixtureID: String
    let fixtureSHA256: String
    init(fixtureID: String, fixtureSHA256: String) throws {
        guard InspectionPackageValidationV2.validToken(fixtureID, maximumBytes: 160),
              KernelCanonicalHashV1.validSHA256(fixtureSHA256) else {
            throw PackageEvolutionFailureV1.invalidValue
        }
        self.fixtureID = fixtureID; self.fixtureSHA256 = fixtureSHA256
    }
}

/// Exact bounded two-shape fixture matrix. Each consumer must receive one
/// minimal and one representative fixture, and the two fixture identities and
/// bytes must differ so a duplicated token cannot masquerade as coverage.
struct PackageSandboxFixtureMatrixV1: Sendable {
    let minimal: [PackageSandboxCheckKindV1: PackageSandboxFixtureV1]
    let representative: [PackageSandboxCheckKindV1: PackageSandboxFixtureV1]

    init(minimal: [PackageSandboxCheckKindV1: PackageSandboxFixtureV1],
         representative: [PackageSandboxCheckKindV1: PackageSandboxFixtureV1]) throws {
        self.minimal = minimal; self.representative = representative
        try validate()
    }

    func validate() throws {
        let consumers = Set(PackageSandboxCheckKindV1.allCases)
        guard Set(minimal.keys) == consumers, Set(representative.keys) == consumers,
              PackageSandboxCheckKindV1.allCases.allSatisfy({ kind in
                  guard let first = minimal[kind], let second = representative[kind] else { return false }
                  return first.fixtureID != second.fixtureID && first.fixtureSHA256 != second.fixtureSHA256
              }) else { throw PackageEvolutionFailureV1.incompleteSandbox }
    }

    func fixture(shape: PackageSandboxFixtureShapeV1,
                 kind: PackageSandboxCheckKindV1) -> PackageSandboxFixtureV1? {
        switch shape {
        case .minimal: return minimal[kind]
        case .representative: return representative[kind]
        }
    }
}

struct PackageSandboxRunnerV1: Sendable {
    let executor: any PackageSandboxCheckExecutingV1
    let activationObserver: any PackageSandboxActivationObservingV1

    init(executor: any PackageSandboxCheckExecutingV1,
         activationObserver: any PackageSandboxActivationObservingV1) {
        self.executor = executor; self.activationObserver = activationObserver
    }

    init(activationObserver: any PackageSandboxActivationObservingV1) {
        executor = CanonicalPackageSandboxConsumerExecutorV1()
        self.activationObserver = activationObserver
    }

    func run(
        runID: UUID,
        workspaceID: WorkspaceID,
        release: InspectionPackageReleaseV1,
        semanticDiff: PackageSemanticDiffV1,
        exactHead: String,
        fixtures: PackageSandboxFixtureMatrixV1,
        mutationID: MutationIDV1
    ) async throws -> PackageSandboxRunV1 {
        try release.validate(); try semanticDiff.validate()
        try fixtures.validate()
        guard release.packageReleaseID == semanticDiff.target.packageReleaseID else {
            throw PackageEvolutionFailureV1.incompleteSandbox
        }
        let before = try await activationObserver.activePointerStateSHA256(
            workspaceID: workspaceID, packageID: release.packageID
        )
        guard KernelCanonicalHashV1.validSHA256(before) else {
            throw PackageEvolutionFailureV1.incompleteSandbox
        }
        var results: [PackageSandboxCheckResultV1] = []
        for kind in PackageSandboxCheckKindV1.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            for shape in PackageSandboxFixtureShapeV1.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let fixture = fixtures.fixture(shape: shape, kind: kind) else {
                    throw PackageEvolutionFailureV1.incompleteSandbox
                }
                let outcome: PackageSandboxExecutionOutcomeV1
                if let shaped = executor as? any PackageSandboxShapeCheckExecutingV1 {
                    outcome = try await shaped.execute(
                        kind: kind, shape: shape, fixtureID: fixture.fixtureID,
                        fixtureSHA256: fixture.fixtureSHA256,
                        release: release, semanticDiff: semanticDiff
                    )
                } else {
                    outcome = try await executor.execute(
                        kind: kind, fixtureID: fixture.fixtureID,
                        fixtureSHA256: fixture.fixtureSHA256,
                        release: release, semanticDiff: semanticDiff
                    )
                }
                guard outcome.activationEvidence == .notAttempted else {
                    throw PackageEvolutionFailureV1.incompleteSandbox
                }
                results.append(PackageSandboxCheckResultV1(
                    kind: kind, shape: shape, fixtureID: fixture.fixtureID,
                    fixtureSHA256: fixture.fixtureSHA256,
                    resultSHA256: outcome.resultSHA256,
                    disposition: outcome.disposition,
                    activationEvidence: outcome.activationEvidence
                ))
            }
        }
        let after = try await activationObserver.activePointerStateSHA256(
            workspaceID: workspaceID, packageID: release.packageID
        )
        guard KernelCanonicalHashV1.validSHA256(after), before == after else {
            throw PackageEvolutionFailureV1.incompleteSandbox
        }
        return try PackageSandboxRunV1(
            runID: runID, workspaceID: workspaceID,
            packageReleaseID: release.packageReleaseID,
            packageSHA256: release.packageSHA256,
            workflowSHA256: release.workflowSHA256,
            semanticDiffSHA256: semanticDiff.diffSHA256,
            exactHead: exactHead,
            activePointerStateBeforeSHA256: before,
            activePointerStateAfterSHA256: after,
            checks: results, mutationID: mutationID
        )
    }
}

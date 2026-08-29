import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V9_07CompatibilityPolicyTests: XCTestCase {
    func testV23P03C37TypedPoseContractAnchor() throws {
        let axis = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c37.anchor"),
            localizedLabelKey: "pose.c37.anchor",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [axis])
        XCTAssertEqual(try registry.descriptor(for: axis.axisID), axis)
    }
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    func testV23P03C40Snapshot3IsReadableProvisionalAndSnapshot2RemainsWriter() throws {
        let policy = ReleasedDataCompatibilityPolicyV1.exactHead(
            candidateHead: String(repeating: "4", count: 40)
        )
        let path = try policy.dataManifest.path(for: .reportOpenJSON)
        XCTAssertEqual(path.readableVersions, ["snapshot1", "snapshot2", "snapshot3"])
        XCTAssertEqual(path.currentWriterVersion, "snapshot2")
        XCTAssertNoThrow(try path.validateReadableVersion("snapshot3"))
        XCTAssertThrowsError(try path.validateWriterVersion("snapshot3")) {
            XCTAssertEqual($0 as? CompatibilityContractErrorV1, .noncurrentWriterVersion)
        }
        XCTAssertEqual(
            ReportSnapshotEncoderV1.authorityCriterionWriterStatus,
            "PROVISIONAL_READ_ONLY_PRE_S10"
        )
    }

    func testV9_07A01DeterministicBoundaryAndInternationalSeedCases() throws {
        let policy = ReleasedDataCompatibilityPolicyV1.current
        let corpus = try V907CompatibilitySupport.corpus()
        let seed = try V907CompatibilitySupport.seed()
        let metadata = try V907CompatibilitySupport.seedMetadata()
        try policy.validate()
        try seed.validate(against: policy)

        let expectedVariants = ["minimum", "maximal", "unicode", "rtl", "long", "empty", "dst"]
        XCTAssertEqual(metadata.schema, "V21P01C07PreV23SeedV1")
        XCTAssertEqual(metadata.schemaVersion, 1)
        XCTAssertTrue(CompatibilityCanonicalV1.validSHA256(metadata.artifactDigest))
        XCTAssertEqual(metadata.generator.name, "p01_c07_contracts.py")
        XCTAssertEqual(metadata.generator.version, "p01-c07-seed-v1")
        XCTAssertEqual(metadata.generator.seed, 230_107)
        XCTAssertEqual(metadata.scenarioTags, expectedVariants.sorted())
        XCTAssertEqual(metadata.workspaceVariants.map(\.id), expectedVariants)
        XCTAssertEqual(metadata.workspaceVariants.map(\.recordCount), [1, 32, 2, 2, 128, 0, 2])
        XCTAssertEqual(metadata.workspaceVariants.filter(\.dstBoundary).map(\.id), ["dst"])
        XCTAssertEqual(metadata.workspaceVariants.filter(\.unicode).map(\.id), ["unicode", "rtl"])
        XCTAssertTrue(metadata.immutable && metadata.synthetic)
        XCTAssertFalse(metadata.containsCustomerData || metadata.containsSecrets)

        for token in expectedVariants {
            XCTAssertTrue(
                V907CompatibilitySupport.containsCase(corpus, tokens: [token]),
                "Missing deterministic \(token) seed case"
            )
        }
        let generated = corpus.cases.filter { $0.source == .deterministicGenerator }
        XCTAssertFalse(generated.isEmpty)
        XCTAssertTrue(generated.allSatisfy { $0.generatorVersion != nil && $0.generatorSeed != nil })
        XCTAssertTrue(corpus.cases.allSatisfy { $0.synthetic && !$0.containsCustomerData && !$0.containsSecrets })
    }

    func testV9_07H01FutureChangedDigestHostileArchiveAndPrivacyRejection() throws {
        let policy = ReleasedDataCompatibilityPolicyV1.current
        let corpus = try V907CompatibilitySupport.corpus()
        try corpus.validate(against: policy.dataManifest)
        let template = try XCTUnwrap(corpus.cases.first)

        let future = V907CompatibilitySupport.replacing(
            template,
            artifactVersion: "999",
            kind: .hostile,
            expectedDisposition: .failsClosedUnsupportedVersion
        )
        XCTAssertNoThrow(try future.validate(against: policy.dataManifest))
        XCTAssertThrowsError(
            try policy.dataManifest.validateReadableVersion("999", for: template.family)
        ) { XCTAssertEqual($0 as? CompatibilityContractErrorV1, .unsupportedVersion) }

        var changedCases = corpus.cases
        let changedDigest = template.artifactSHA256 == String(repeating: "f", count: 64)
            ? String(repeating: "e", count: 64)
            : String(repeating: "f", count: 64)
        changedCases[0] = V907CompatibilitySupport.replacing(
            template,
            artifactSHA256: changedDigest
        )
        let changed = CompatibilityCorpusManifestV1(
            corpusID: corpus.corpusID,
            sealState: corpus.sealState,
            policyManifestSHA256: corpus.policyManifestSHA256,
            cases: changedCases
        )
        XCTAssertThrowsError(try changed.validateExtension(of: corpus)) {
            XCTAssertEqual($0 as? CompatibilityContractErrorV1, .quarantinedCaseIDReuse)
        }

        for token in ["tamper", "truncat", "path", "bomb"] {
            XCTAssertTrue(
                V907CompatibilitySupport.containsCase(corpus, tokens: [token]),
                "Missing hostile \(token) archive case"
            )
        }
        let canonical = try corpus.canonicalData()
        XCTAssertThrowsError(
            try CompatibilityCorpusManifestV1.decodeCanonical(
                Data(canonical.dropLast()),
                against: policy.dataManifest
            )
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        )
        object["unexpectedSecretBearingExtension"] = true
        let alternate = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        XCTAssertThrowsError(try CompatibilityCorpusManifestV1.decodeCanonical(
            alternate,
            against: policy.dataManifest
        ))
        XCTAssertThrowsError(try V907CompatibilitySupport.replacing(
            template,
            artifactRelativePath: "../customer.json"
        ).validate(against: policy.dataManifest))
        XCTAssertThrowsError(try V907CompatibilitySupport.replacing(
            template,
            containsCustomerData: true
        ).validate(against: policy.dataManifest))
        XCTAssertThrowsError(try V907CompatibilitySupport.replacing(
            template,
            containsSecrets: true
        ).validate(against: policy.dataManifest))
    }

    func testV9_07R01ReplayQuarantineImmutabilityAndAcceptanceModeSeparation() throws {
        let policy = ReleasedDataCompatibilityPolicyV1.current
        let corpus = try V907CompatibilitySupport.corpus()
        let seed = try V907CompatibilitySupport.seed()
        try seed.validate(against: policy)
        let priorSeedDigest = try seed.canonicalSHA256()
        let selected = corpus.caseIDs(for: .representativeSentinel)
        let byID = Dictionary(uniqueKeysWithValues: corpus.cases.map { ($0.caseID, $0) })
        let passed = try selected.map { caseID in
            let item = try XCTUnwrap(byID[caseID])
            return try V907CompatibilitySupport.result(
                for: item,
                observedOutputSHA256: V907CompatibilitySupport.executeCase(
                    for: item
                )
            )
        }
        let accepted = try V907CompatibilitySupport.receipt(
            runID: "v23-p01-c07-r01",
            corpus: corpus,
            selection: .representativeSentinel,
            mode: .acceptingFailFast,
            results: passed
        )
        try accepted.requireAccepting(against: corpus)
        XCTAssertEqual(try accepted.replayDisposition(comparedTo: accepted), .idempotentReplay)

        let first = try XCTUnwrap(byID[try XCTUnwrap(selected.first)])
        let nilObserved = CompatibilityCaseRunResultV1(
            caseID: first.caseID,
            caseManifestSHA256: try first.canonicalSHA256(),
            outcome: .passed,
            normalizedOutputSHA256: nil
        )
        XCTAssertThrowsError(try nilObserved.validate()) {
            XCTAssertEqual($0 as? CompatibilityContractErrorV1, .invalidRunReceipt)
        }
        let nilObservedReceipt = try V907CompatibilitySupport.receipt(
            runID: "v23-p01-c07-r01-output-nil",
            corpus: corpus,
            selection: .representativeSentinel,
            mode: .acceptingFailFast,
            results: [nilObserved]
        )
        XCTAssertThrowsError(try nilObservedReceipt.validate(against: corpus)) {
            XCTAssertEqual($0 as? CompatibilityContractErrorV1, .invalidRunReceipt)
        }
        XCTAssertFalse(nilObservedReceipt.isAccepting)
        XCTAssertThrowsError(try nilObservedReceipt.requireAccepting(against: corpus))
        let expectedOutput = first.normalizedExpectedSHA256 ?? first.artifactSHA256
        let mismatchedOutput = expectedOutput == String(repeating: "f", count: 64)
            ? String(repeating: "e", count: 64)
            : String(repeating: "f", count: 64)
        let mismatchedResult = try V907CompatibilitySupport.result(
            for: first,
            observedOutputSHA256: mismatchedOutput
        )
        let mismatchedReceipt = try V907CompatibilitySupport.receipt(
            runID: "v23-p01-c07-r01-output-mismatch",
            corpus: corpus,
            selection: .representativeSentinel,
            mode: .acceptingFailFast,
            results: [mismatchedResult]
        )
        XCTAssertThrowsError(try mismatchedReceipt.validate(against: corpus)) {
            XCTAssertEqual($0 as? CompatibilityContractErrorV1, .invalidRunReceipt)
        }
        XCTAssertThrowsError(try mismatchedReceipt.requireAccepting(against: corpus))

        let changedResult = try V907CompatibilitySupport.result(
            for: XCTUnwrap(byID[selected[0]]),
            outcome: .failed,
            failureCode: "changed_input"
        )
        let changedRun = try V907CompatibilitySupport.receipt(
            runID: accepted.runID,
            corpus: corpus,
            selection: .representativeSentinel,
            mode: .acceptingFailFast,
            results: [changedResult]
        )
        XCTAssertThrowsError(try changedRun.replayDisposition(comparedTo: accepted)) {
            XCTAssertEqual($0 as? CompatibilityContractErrorV1, .quarantinedRunIDReuse)
        }

        let diagnosticResults = try selected.enumerated().map { offset, caseID in
            let item = try XCTUnwrap(byID[caseID])
            let outcome: CompatibilityCaseRunOutcomeV1 = offset == 0 ? .failed : .passed
            if outcome == .passed {
                let observedOutputSHA256 = try V907CompatibilitySupport.executeCase(
                    for: item
                )
                return try V907CompatibilitySupport.result(
                    for: item,
                    observedOutputSHA256: observedOutputSHA256
                )
            } else {
                return try V907CompatibilitySupport.result(
                    for: item,
                    outcome: outcome,
                    failureCode: "diagnostic_failure"
                )
            }
        }
        let diagnostic = try V907CompatibilitySupport.receipt(
            runID: "v23-p01-c07-r01-diagnostic",
            corpus: corpus,
            selection: .representativeSentinel,
            mode: .diagnosticContinue,
            results: diagnosticResults
        )
        try diagnostic.validate(against: corpus)
        XCTAssertFalse(diagnostic.isAccepting)
        XCTAssertThrowsError(try diagnostic.requireAccepting(against: corpus))

        let priorDigest = try corpus.canonicalSHA256()
        try corpus.validate(against: policy.dataManifest, previous: corpus)
        XCTAssertEqual(try corpus.canonicalSHA256(), priorDigest)
        XCTAssertEqual(try V907CompatibilitySupport.seed().canonicalSHA256(), priorSeedDigest)
        let historicPDF = try V907CompatibilitySupport.fixtureData(
            "V21P01C07HistoricReportV1",
            extension: "pdf"
        )
        XCTAssertEqual(
            historicPDF,
            try V907CompatibilitySupport.fixtureData("V21P01C07HistoricReportV1", extension: "pdf")
        )
    }
}

private final class C27V907PolicyTypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(ExternalKeyNormalizationV1.allCases, [.exactNFC, .asciiCaseInsensitive])
        XCTAssertEqual(AssetLocatorStateV1.allCases.count, 4)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionStartsWork)
    }
}

extension V9_07CompatibilityPolicyTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension V9_07CompatibilityPolicyTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistentSchemaVersion: 21, recordsSchemaVersion: 20)
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.externalCopyAvailabilityClaimed)
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.liveRestorePermitted)
    }
}

extension V9_07CompatibilityPolicyTests {
    func testV23P03C18CompatibilityClassesRemainClosedAndVersioned() throws {
        XCTAssertEqual(PackageSemanticDiffClassificationV1.allCases.count, 5)
        XCTAssertEqual(
            PackageSemanticDiffClassificationV1.allCases.map(\.rawValue),
            [
                "NO_CHANGE", "ADDITIVE_DRAFT_SAFE", "DRAFT_MIGRATION_REQUIRED",
                "ACTIVE_SESSION_INCOMPATIBLE", "INVALID"
            ]
        )
        XCTAssertEqual(PackageSemanticGraphV1.schemaVersion, 1)
    }
}

extension V9_07CompatibilityPolicyTests {
    func testV23P03C15PolicyAndPackageReferencesRemainComparable() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_108)
        try fixture.policyReference.validate()
        XCTAssertEqual(fixture.manifest.packageReleases, [fixture.packageRelease])
        XCTAssertEqual(fixture.item.policyReferences, [fixture.policyReference])
        XCTAssertNotEqual(fixture.manifest.manifestSHA256, fixture.alternateManifest.manifestSHA256)
    }
}

extension V9_07CompatibilityPolicyTests {
    func testV23P03C36CompatibilityBoundaryRequiresRecords15AndPersistent16() throws {
        XCTAssertNoThrow(try V16FieldDraftImportBoundaryV1.validate(persistent: 16, records: 15))
        XCTAssertThrowsError(try V16FieldDraftImportBoundaryV1.validate(persistent: 15, records: 15))
        XCTAssertThrowsError(try V16FieldDraftImportBoundaryV1.validate(persistent: 16, records: 14))
        XCTAssertEqual(PersistentSchemaReleaseRegistryV1.activeVersionIdentifier, PersistentSchemaV16.versionIdentifier)
        XCTAssertEqual(PersistentSchemaReleaseRegistryV1.activeCompatibilityID, PersistentSchemaReleaseV1.v16.compatibilityID)
        XCTAssertEqual(PersistentSchemaReleaseV1.v16.models.count, 64)
    }
}

extension V9_07CompatibilityPolicyTests {
    func testV23P03C41CompatibilityRoundTripRetainsPackageAndDescriptorIdentity() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_070)
        let encoded = try FunctionalRelationshipCanonicalCodecV1.encode(fixture.descriptor)
        let decoded = try FunctionalRelationshipCanonicalCodecV1.decode(
            FunctionalRelationshipTypeDescriptorV1.self, from: encoded
        )

        XCTAssertEqual(decoded, fixture.descriptor)
        XCTAssertEqual(decoded.packageRelease, fixture.packageRelease)
        XCTAssertEqual(decoded.sourceCatalogRelease.packageRelease, fixture.packageRelease)
        XCTAssertEqual(decoded.targetCatalogRelease.packageRelease, fixture.packageRelease)
        XCTAssertEqual(decoded.descriptorSHA256, fixture.descriptor.descriptorSHA256)
        try decoded.validate(sourceCatalog: fixture.sourceCatalog, targetCatalog: fixture.targetCatalog)
    }
}

extension V9_07CompatibilityPolicyTests {
    func testV23P03C13CompatibilityCodecPreservesVisibilityAndFreshManifestBinding() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_907)
        let visibilityBytes = try EvidenceAssuranceCanonicalCodecV1.encode(fixture.routineVisibility)
        let decodedVisibility = try EvidenceAssuranceCanonicalCodecV1.decode(
            EvidenceVisibilityV1.self, from: visibilityBytes
        )
        let manifestBytes = try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerManifest)
        let decodedManifest = try EvidenceAssuranceCanonicalCodecV1.decode(
            AssuranceManifestV1.self, from: manifestBytes
        )

        XCTAssertEqual(decodedVisibility, fixture.routineVisibility)
        XCTAssertEqual(decodedManifest, fixture.customerManifest)
        XCTAssertEqual(try EvidenceAssuranceCanonicalCodecV1.encode(decodedManifest), manifestBytes)
        try decodedManifest.validateFresh(preview: fixture.customerPreview)
    }
}

extension V9_07CompatibilityPolicyTests {
    func testV23P03C14PolicySupersessionIsRevisionBound() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_007)
        try fixture.supersedingPolicy.validateSuccessor(of: fixture.policy)
        XCTAssertEqual(fixture.supersedingPolicy.revision, fixture.policy.revision + 1)
        XCTAssertEqual(fixture.supersedingPolicy.supersedesReleaseID, fixture.policy.releaseID)
        XCTAssertNotEqual(fixture.supersedingPolicy.mutationID, fixture.policy.mutationID)
    }

    func testV23P03C19CompatibilityUsesForwardFixAfterV18() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        try MeasurementIntegrityForwardFixPolicyV1.requireForwardFix(
            afterFirstWrite: true, requestedGeneration: 18
        )
        XCTAssertThrowsError(try MeasurementIntegrityForwardFixPolicyV1.requireForwardFix(
            afterFirstWrite: true, requestedGeneration: 17
        ))
        try fixture.currentCalibration.validate()
    }

    func testC20PrivacyTransformPolicyUsesClosedKindsAndReasons() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        try fixture.policy.validate()
        XCTAssertEqual(fixture.policy.allowedTransformKinds, PrivacyTransformKindV1.allCases.sorted { $0.rawValue < $1.rawValue })
        XCTAssertEqual(fixture.policy.allowedReasons, PrivacyTransformReasonV1.allCases.sorted { $0.rawValue < $1.rawValue })
        XCTAssertTrue(fixture.policy.reviewRequired)
        XCTAssertTrue(fixture.policy.denyByDefault)
    }
}

extension V9_07CompatibilityPolicyTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension V9_07CompatibilityPolicyTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveySemanticCompatibilityV1.invalid.rawValue, "INVALID")
        XCTAssertEqual(SurveyAdoptionDispositionV1.blocked.rawValue, "BLOCKED")
        XCTAssertEqual(SurveyDefinitionLimitsV1.maximumFacts, 2_048)
    }
}
extension V9_07CompatibilityPolicyTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension V9_07CompatibilityPolicyTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}

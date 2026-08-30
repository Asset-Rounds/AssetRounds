import Foundation
import XCTest

@testable import FieldEvidenceApp

private final class C50CompatibilityPolicyTests: XCTestCase {
    func testV23P03C50SuccessorIsForwardFixAndExactOldReleaseRemainsReadable() throws {
        let mapping = try IncumbentMappingManifestV1(mappings: [
            IncumbentFieldMappingV1(
                externalHeader: "Version",
                canonicalField: .fileFormatVersion,
                required: true
            ),
        ])
        let budget = try IncumbentFileBudgetV1(
            maximumByteCount: 1_024,
            maximumRowCount: 10,
            maximumColumnCount: 1,
            maximumScalarCountPerCell: 128
        )
        let profileID = UUID(uuidString: "c5000000-0000-4000-8000-000000000701")!
        let adapterID = UUID(uuidString: "c5000000-0000-4000-8000-000000000700")!
        let old = try IncumbentFileProfileReleaseV1(
            profileID: profileID,
            adapterID: adapterID,
            releaseID: UUID(uuidString: "c5000000-0000-4000-8000-000000000702")!,
            revision: 1,
            providerDisplayToken: "synthetic",
            uniformTypeIdentifiers: ["public.comma-separated-values-text"],
            filenameExtensions: ["csv"],
            delimiter: .comma,
            orderedHeaders: ["Version"],
            versionHeader: "Version",
            versionValue: "V1",
            direction: .importOnly,
            budget: budget,
            mappingManifest: mapping,
            externalKeyPolicy: .exactOpaqueStableKey,
            timeZonePolicy: .noTemporalFields
        )
        let successor = try IncumbentFileProfileReleaseV1(
            profileID: profileID,
            adapterID: adapterID,
            releaseID: UUID(uuidString: "c5000000-0000-4000-8000-000000000703")!,
            revision: 2,
            providerDisplayToken: "synthetic",
            uniformTypeIdentifiers: ["public.comma-separated-values-text"],
            filenameExtensions: ["csv"],
            delimiter: .comma,
            orderedHeaders: ["Version"],
            versionHeader: "Version",
            versionValue: "V2",
            direction: .importOnly,
            budget: budget,
            mappingManifest: mapping,
            externalKeyPolicy: .exactOpaqueStableKey,
            timeZonePolicy: .noTemporalFields,
            predecessorReleaseID: old.releaseID,
            predecessorReleaseSHA256: old.releaseSHA256
        )
        try successor.validateSuccessor(of: old)

        let disabled = try IncumbentSelectionReceiptV1(
            receiptID: UUID(uuidString: "c5000000-0000-4000-8000-000000000704")!,
            disposition: .disabledNoSelectedProfile,
            selectedRelease: nil,
            sanitizedFixtureProvenance: "Synthetic conformance only",
            targetWorkflow: "NO_PROFILE",
            fileVersion: nil,
            direction: nil,
            stableKeyMeaning: "No selected stable key",
            termsDisposition: .unavailable,
            evidenceDate: Date(timeIntervalSince1970: 1_800_000_000),
            evidenceExpiresAt: nil
        )
        let availability = try TypedAvailabilityAndFallbackReceiptV1(
            candidateHead: "1c8b3d99826a207d3b18b3e0429231c31804f317",
            candidateTree: "3107903158238e5e5eaed78322c3564b06c648e2",
            providerID: "V23_P03_C50",
            providerSliceDigest: String(repeating: "c", count: 64),
            consumerID: "V23_P04_C37",
            capabilityID: .filesAndShare,
            availabilityReason: .workspacePolicyDisabled,
            mandatoryCoreComplete: true,
            visibleFallback: .saveLocally,
            persistenceDisposition: .noCanonicalEffectUntilAcceptance,
            dataDisposition: .priorHistoryPreserved,
            reentryTrigger: .capabilityStateChanged,
            localizedVisibleStateKey: "incumbent.profile.disabled.state",
            localizedVisibleCopyKey: "incumbent.profile.disabled.copy",
            localizedNextActionKey: "incumbent.profile.disabled.action",
            fallbackTestArtifactIDs: ["V23-P03-C50-A01-FALLBACK"],
            evidenceArtifactIDs: ["V23-P03-C50-A01-RECEIPT"],
            zeroUnsupportedPublicClaim: true
        )
        let registry = try ClosedIncumbentAdapterRegistryV1(
            currentProductionReleases: [],
            historicReleases: [old, successor],
            selection: disabled,
            selectionHistory: [disabled],
            availabilityReceipt: availability
        )
        XCTAssertEqual(try registry.exactHistoricRelease(id: old.releaseID, sha256: old.releaseSHA256), old)
    }
}

private final class C45CompatibilityPolicyTypedTests: XCTestCase {
    func testV23P03C45CompatibilityFreezesTemplateRenderingPolicies() {
        XCTAssertEqual(AssetLabelLineBreakPolicyV1.allCases, [.fixedGraphemeTailTruncation])
        XCTAssertEqual(AssetLabelQRCorrectionLevelV1.allCases, [.medium])
        XCTAssertEqual(AssetLabelQRCorrectionLevelV1.medium.rawValue, "M")
    }
}

private final class C30EvidenceContextAnchorV9_07CompatibilityPolicy: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

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
private final class C31LightingAnchorV907CompatibilityPolicyTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private final class C33TemporalEvidenceAnchorV907CompatibilityPolicy: XCTestCase {
    func testC33V907CompatibilityPolicyCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "compatibility.temporal-evidence-v1",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "compatibility.temporal-evidence-v1",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV907CompatibilityPolicy: XCTestCase {
    func testC32V907CompatibilityPolicyCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .report,
            fieldID: "compatibility.released-report",
            value: .text("historic interpretation unchanged")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .report,
            fieldID: "compatibility.released-report",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46V907CompatibilityPolicyTests: XCTestCase {
    func testC46CompatibilityPolicyPreservesExactContactValue() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "compatibility-policy",
            kind: .email,
            handoff: .email,
            slot: 46007
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_07CompatibilityPolicyTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_07CompatibilityPolicyTests_swift_Tests: XCTestCase {
    func testC47V907CompatibilityPolicyTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_07CompatibilityPolicyTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_07CompatibilityPolicyTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_07CompatibilityPolicyTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_07CompatibilityPolicyTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_07CompatibilityPolicyTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_07CompatibilityPolicyTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_07CompatibilityPolicyTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityKindV1CompatibilityAdapterV2.disposition(.survey), .exactV1)
        XCTAssertEqual(ActivityKindV1CompatibilityAdapterV2.v1(.survey), .survey)
    }
}

private final class C48PortableReviewV907CompatibilityPolicyTests: XCTestCase {
    func testC48ReleasedProtocolFailsClosedWithoutRewritingHistory() {
        XCTAssertTrue(C48PortableReviewReleasedDataCompatibilityBoundaryV1.exchangeProtocolIsSeparateFromWorkspaceSchema)
        XCTAssertTrue(C48PortableReviewReleasedDataCompatibilityBoundaryV1.derivedHistoryNeverRequiresHistoricSnapshotRewrite)
        XCTAssertTrue(C48PortableReviewReleasedDataCompatibilityBoundaryV1.unknownProtocolVersionsFailClosed)
    }
}
private final class C49WorkResourceCompatibilityBoundaryTests: XCTestCase {
    func testReleasedRawValuesAreStable() {
        XCTAssertEqual(WorkResourceSubjectKindV1.workPacket.rawValue, "WORK_PACKET")
        XCTAssertEqual(WorkResourceDispositionV1.reversed.rawValue, "REVERSED")
    }
}

extension C50CompatibilityPolicyTests {
    func testV23P03C51CompatibilityFailsClosedForNewerSchedulePayloads() throws {
        try ScheduleCompatibilityPolicyV1.current.validate()
        XCTAssertTrue(
            ScheduleCompatibilityPolicyV1.persistentSchemaVersion == 27
                && ScheduleCompatibilityPolicyV1.recordsSchemaVersion == 26
                && ScheduleCompatibilityPolicyV1.current.allDaysCompatibilityParity
                && ScheduleCompatibilityPolicyV1.current
                    .unknownNewerSchedulePayloadDisposition == "FAIL_CLOSED"
        )
    }
}

extension V9_07CompatibilityPolicyTests {
    func testV23P03C34CompatibilityFailsClosedForUnknownOrCorruptSceneState() throws {
        let port = InMemorySceneNavigationDeviceStatePortV1()
        let adapter = SceneNavigationStateAdapterV1(port: port)
        for payload in [Data(#"{"schemaVersion":2}"#.utf8), Data("corrupt".utf8)] {
            try port.saveSceneNavigationData(payload)
            let expected: SceneNavigationLoadResultV1 = payload.first == 123
                ? .discarded(.unsupportedSnapshotVersion)
                : .discarded(.corruptSnapshot)
            XCTAssertEqual(try adapter.loadAndReconcile(), expected)
            XCTAssertNil(port.data)
        }
    }
}

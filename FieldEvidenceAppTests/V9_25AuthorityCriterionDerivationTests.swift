import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_25AuthorityCriterionDerivationTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)
    private let fixedDate = Date(timeIntervalSince1970: 1_735_689_600.125)

    // The five card-level selectors are kept as stable entry points for the
    // portable C40 verifier; the focused tests below remain independently
    // selectable during development.
    func testV9_AuthorityCriterionG01SourceApplicabilityCriterionAndSeverityMatrix() throws {
        try testV23P03C40ClosedEnumsSchemaAndProjectionPolicies()
        try testV23P03C40CompleteAggregateBindsOldAndNewAuthorityReleases()
        try testV23P03C40EveryApplicabilityStateRequiresOnlyItsDeclaredReason()
    }

    func testV9_AuthorityCriterionA01MeasurementUnitsAndDeterministicDerivation() throws {
        try testV23P03C40ExactMeasurementAndDerivationRetainCanonicalProvenance()
        try testV23P03C40DeterministicEvaluatorRejectsHostileInputs()
    }

    func testV9_AuthorityCriterionH01RightsJurisdictionEvaluatorAndClaimBoundariesFailClosed() throws {
        try testV23P03C40RightsWorkspaceAndExpiredQualificationHostilesFailClosed()
        try testV23P03C40ClosedEnumsSchemaAndProjectionPolicies()
    }

    func testV9_AuthorityCriterionI01InterruptedAdmissionBindingDerivationAndReplayRecover() throws {
        try testV23P03C40CanonicalReplayTamperAndAllPersistenceRows()
        try testV23P03C40MutationCoordinatorPredecessorConcurrencyAndReceiptReplay()
    }

    func testV9_AuthorityCriterionR01BackupRestoreSearchReportImportAndErasePinHistory() throws {
        try testV23P03C40SearchProjectionUsesOnlyBoundedWorkFields()
        try testV23P03C40PortableCorpusRemainsStaticAndProvisional()
    }

    func testV23P03C40ClosedEnumsSchemaAndProjectionPolicies() throws {
        XCTAssertEqual(
            Set(AuthoritySourceTypeV1.allCases),
            [.guidance, .voluntaryStandard, .adoptedRule, .manufacturerInstruction,
             .contractOrInsurer, .ownerPolicy]
        )
        XCTAssertEqual(
            Set(LicenseStorageDispositionV1.allCases),
            [.metadataAndLocatorOnly, .lawfulContentReference, .externalLocatorOnly, .notStored]
        )
        XCTAssertEqual(
            Set(RequirementBasisKindV1.allCases),
            [.adoptedRequirement, .contractRequirement, .ownerPolicy, .declaredScreeningBasis]
        )
        XCTAssertEqual(
            Set(ApplicabilityDispositionV1.allCases),
            [.applicable, .notApplicableWithReason, .unknown, .conflictReviewRequired, .unsupported]
        )
        XCTAssertEqual(
            Set(ScreeningCriterionResultV1.allCases),
            [.meetsScreeningCriterion, .doesNotMeet, .inconclusive, .notEvaluated]
        )
        XCTAssertEqual(
            Set(MeasurementSamplingPolicyV1.allCases), [.single, .orderedSeries, .boundedSet]
        )
        XCTAssertEqual(
            Set(DerivedFactEvaluatorKindV1.allCases),
            [.identityCanonical, .arithmeticMeanCanonical, .ratioPercent]
        )
        XCTAssertEqual(
            Set(DerivedFactDispositionV1.allCases), [.evaluated, .inconclusive, .notEvaluated]
        )

        XCTAssertEqual(PersistentSchemaV11.versionIdentifier, Schema.Version(11, 0, 0))
        XCTAssertEqual(PersistentSchemaV11.models.count, 42)
        XCTAssertEqual(PersistentSchemaReleaseRegistryV1.activeRelease, .v11)
        XCTAssertEqual(PersistentSchemaReleaseRegistryV1.activeVersionIdentifier, PersistentSchemaV11.versionIdentifier)
        XCTAssertEqual(
            ObjectIdentifier(PersistentSchemaReleaseRegistryV1.activeMigrationPlan),
            ObjectIdentifier(PersistentSchemaMigrationPlanV10.self)
        )
        XCTAssertNoThrow(try PersistentSchemaReleaseRegistryV1.validate())
        XCTAssertEqual(PersistentSchemaMigrationPlanV10.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV10.stages.count, 1)

        XCTAssertEqual(
            SearchAuthorityCriterionPersistencePolicyV1.fieldIDs,
            ["authority_source", "applicability_disposition", "criterion_result", "severity_level", "measurement_protocol"]
        )
        XCTAssertEqual(SearchAuthorityCriterionPersistencePolicyV1.sourceKind, "WORK")
        XCTAssertTrue(SearchAuthorityCriterionPersistencePolicyV1.excludesLicensedSourceBytes)
        XCTAssertTrue(SearchAuthorityCriterionPersistencePolicyV1.excludesRawLocators)
        XCTAssertTrue(SearchAuthorityCriterionPersistencePolicyV1.excludesLegalSafetyComplianceClaims)
        XCTAssertTrue(
            SearchAuthorityCriterionPersistencePolicyV1.fieldIDs.allSatisfy {
                SearchAuthorityCriterionPersistencePolicyV1.accepts(fieldID: $0)
            }
        )
        XCTAssertFalse(SearchAuthorityCriterionPersistencePolicyV1.accepts(fieldID: "licensed_source_bytes"))

        XCTAssertEqual(ReportAuthorityCriterionProjectionPolicyV1.sectionID, "authority-criterion")
        XCTAssertEqual(ReportAuthorityCriterionProjectionPolicyV1.requiredWording, "assessed against")
        XCTAssertEqual(ReportAuthorityCriterionProjectionPolicyV1.privacyClass, .audienceSafe)
        XCTAssertTrue(ReportAuthorityCriterionProjectionPolicyV1.supports(.openJSON))
        XCTAssertTrue(ReportAuthorityCriterionProjectionPolicyV1.supports(.structuredText))
        XCTAssertFalse(ReportAuthorityCriterionProjectionPolicyV1.supports(.pdf))
        XCTAssertTrue(ReportAuthorityCriterionProjectionPolicyV1.excludesLicensedSourceBytes)
        XCTAssertTrue(ReportAuthorityCriterionProjectionPolicyV1.excludesRawLocators)
        XCTAssertTrue(ReportAuthorityCriterionProjectionPolicyV1.excludesLegalSafetyComplianceClaims)

        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.keys.contains("authority.criterion.assessed_against"))
        XCTAssertEqual(AuthorityCriterionLocalizationPolicyV1.requiredReportWording, "assessed against")
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.excludesLicensedSourceText)
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.excludesRawMeasurementSamples)
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.excludesPrivateLocators)
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.excludesUnsupportedClaims)
        XCTAssertFalse(AuthorityCriterionLocalizationPolicyV1.containsProhibitedClaim(in: ["Assessed against the recorded basis."]))
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.containsProhibitedClaim(in: ["This is certified."]))
        XCTAssertTrue(AuthorityCriterionAccessibilityPolicyV1.textAndIconActionableNextStepRequired)
        XCTAssertFalse(AuthorityCriterionAccessibilityPolicyV1.colorOnlySeverityAllowed)
        XCTAssertTrue(AuthorityCriterionAccessibilityPolicyV1.requiresTextAndIcon(for: AuthorityCriterionAccessibilityIDV1.unknownApplicability.rawValue))
        XCTAssertTrue(AuthorityCriterionAccessibilityPolicyV1.requiresActionableNextStep(for: AuthorityCriterionAccessibilityIDV1.inconclusive.rawValue))
    }

    func testV23P03C40CompleteAggregateBindsOldAndNewAuthorityReleases() throws {
        let fixture = try makeFixture()

        XCTAssertNoThrow(try AuthorityCriterionRegistryV1.validate(fixture.aggregate, workspaceID: fixture.workspaceID))
        XCTAssertEqual(fixture.source.revision, 1)
        XCTAssertEqual(fixture.successorSource.sourceID, fixture.source.sourceID)
        XCTAssertEqual(fixture.successorSource.supersedesReleaseID, fixture.source.releaseID)
        XCTAssertEqual(fixture.context.basisBindings.first?.authorityReleaseID, fixture.source.releaseID)
        XCTAssertEqual(fixture.assessment.includedCriterionIDs, ["criterion.pressure.range", "criterion.screening"])
        XCTAssertEqual(fixture.mapping.sourceScaleReleaseID, fixture.severity.releaseID)
        XCTAssertEqual(fixture.mapping.destinationScaleReleaseID, fixture.successorSeverity.releaseID)
        XCTAssertEqual(fixture.mapping.entries.map(\.sourceLevelID), ["major", "minor"])
        XCTAssertEqual(fixture.classification.result, .meetsScreeningCriterion)
        XCTAssertEqual(fixture.protocolRelease.normativeUnitID, "psi")
        XCTAssertEqual(fixture.provenance.inputs.count, 1)
        XCTAssertEqual(fixture.provenance.disposition, .evaluated)

        let updatedPackage = try PackageReleaseIdentityV1(
            packageID: fixture.package.packageID,
            schemaVersion: fixture.package.schemaVersion,
            contentVersion: fixture.package.contentVersion + 1
        )
        let updatedCatalog = try makeSemanticCatalog(
            packageRelease: updatedPackage, releaseID: id(8_060), releasedAt: fixedDate.addingTimeInterval(20)
        )
        let updatedBinding = try WorkSubjectSemanticBindingSnapshotV1(
            assetID: id(8_007), kindBindingEventID: id(8_061), kindBindingRevision: 2,
            catalogRelease: updatedCatalog.reference, semanticID: "asset.kind.authority",
            workflowPackageReleases: [updatedPackage]
        )
        let updatedScope = try WorkSubjectScopeSnapshotV1(
            snapshotID: id(8_062), workspaceID: fixture.workspaceID, siteID: fixture.context.siteID,
            subjects: fixture.scope.subjects, semanticBindings: [updatedBinding], workspaceRevision: 9,
            recordedAt: fixedDate.addingTimeInterval(20)
        )
        let updatedContext = try ApplicabilityContextSnapshotV1(
            snapshotID: id(8_063), workspaceID: fixture.workspaceID,
            siteID: fixture.context.siteID, activityID: fixture.context.activityID,
            workSubjectScope: updatedScope, packageReleases: [updatedPackage],
            actor: fixture.actor, qualification: fixture.qualification,
            effectiveAt: fixedDate.addingTimeInterval(20), basisBindings: fixture.context.basisBindings,
            disposition: .unknown, dispositionReason: nil,
            recordedAt: fixedDate.addingTimeInterval(21), revision: 2, mutationID: fixture.mutationID
        )
        XCTAssertEqual(updatedContext.packageReleases, [updatedPackage])
        XCTAssertEqual(updatedContext.revision, 2)
        XCTAssertEqual(updatedContext.disposition, .unknown)
        XCTAssertNotEqual(updatedContext.snapshotSHA256, fixture.context.snapshotSHA256)
    }

    func testV23P03C40EveryApplicabilityStateRequiresOnlyItsDeclaredReason() throws {
        let fixture = try makeFixture()
        let states = ApplicabilityDispositionV1.allCases
        let contexts = try states.enumerated().map { offset, disposition in
            try ApplicabilityContextSnapshotV1(
                snapshotID: id(8_100 + offset), workspaceID: fixture.workspaceID,
                siteID: fixture.context.siteID, activityID: id(8_200 + offset),
                workSubjectScope: fixture.scope, packageReleases: [], actor: fixture.actor,
                qualification: nil, effectiveAt: fixedDate,
                basisBindings: fixture.context.basisBindings, disposition: disposition,
                dispositionReason: disposition == .notApplicableWithReason
                    || disposition == .conflictReviewRequired || disposition == .unsupported
                    ? "Recorded review reason" : nil,
                recordedAt: fixedDate.addingTimeInterval(1 + Double(offset)),
                revision: 1, mutationID: fixture.mutationID
            )
        }
        XCTAssertEqual(contexts.map(\.disposition), states)
        XCTAssertEqual(contexts.filter { $0.disposition == .unknown }.count, 1)
        XCTAssertEqual(contexts.filter { $0.disposition == .conflictReviewRequired }.count, 1)

        XCTAssertThrowsError(try ApplicabilityContextSnapshotV1(
            snapshotID: id(8_300), workspaceID: fixture.workspaceID,
            siteID: fixture.context.siteID, activityID: id(8_301), workSubjectScope: fixture.scope,
            packageReleases: [], actor: fixture.actor, qualification: nil, effectiveAt: fixedDate,
            basisBindings: fixture.context.basisBindings, disposition: .conflictReviewRequired,
            dispositionReason: nil, recordedAt: fixedDate.addingTimeInterval(1), revision: 1,
            mutationID: fixture.mutationID
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .invalidValue)
        }
    }

    func testV23P03C40RightsWorkspaceAndExpiredQualificationHostilesFailClosed() throws {
        let fixture = try makeFixture()
        let workspaceString = fixture.workspaceID.rawValue.uuidString.lowercased()
        let sourceDigest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: digest)
        let digestSet = try ContentDigestSetV1([sourceDigest])
        let reference = try ContentReferenceV1(
            workspaceID: workspaceString, contentID: "authority-c40-bytes", byteLength: 128,
            mediaType: "application/pdf", digests: digestSet, byteRole: .immutableOriginal,
            createdAt: "2026-08-27T00:00:00.000Z"
        )
        let lawful = try AuthoritySourceReleaseV1(
            releaseID: id(8_400), workspaceID: fixture.workspaceID, sourceID: id(8_401),
            sourceType: .guidance, designation: "Lawful reference", editionOrRevision: "1",
            publisherDisplay: "Publisher", publicationAt: fixedDate,
            effectiveFrom: fixedDate, licenseStorageDisposition: .lawfulContentReference,
            lawfulContentReference: reference, retrievedAt: fixedDate,
            sourceDigestSHA256: digest, recordedAt: fixedDate.addingTimeInterval(1), revision: 1,
            mutationID: fixture.mutationID
        )
        try reference.validateAuthoritySourceBinding(lawful)
        XCTAssertEqual(lawful.lawfulContentReference, reference)

        XCTAssertThrowsError(try AuthoritySourceReleaseV1(
            releaseID: id(8_410), workspaceID: fixture.workspaceID, sourceID: id(8_411),
            sourceType: .guidance, designation: "Missing lawful bytes", editionOrRevision: "1",
            licenseStorageDisposition: .lawfulContentReference, retrievedAt: fixedDate,
            recordedAt: fixedDate.addingTimeInterval(1), revision: 1, mutationID: fixture.mutationID
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .invalidValue)
        }
        XCTAssertThrowsError(try AuthoritySourceReleaseV1(
            releaseID: id(8_420), workspaceID: fixture.workspaceID, sourceID: id(8_421),
            sourceType: .guidance, designation: "Metadata with bytes", editionOrRevision: "1",
            licenseStorageDisposition: .metadataAndLocatorOnly, lawfulContentReference: reference,
            retrievedAt: fixedDate, recordedAt: fixedDate.addingTimeInterval(1), revision: 1,
            mutationID: fixture.mutationID
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .invalidValue)
        }
        XCTAssertThrowsError(try AuthoritySourceReleaseV1(
            releaseID: id(8_430), workspaceID: fixture.workspaceID, sourceID: id(8_431),
            sourceType: .guidance, designation: "Wrong workspace bytes", editionOrRevision: "1",
            licenseStorageDisposition: .lawfulContentReference,
            lawfulContentReference: try ContentReferenceV1(
                workspaceID: id(9_999).uuidString.lowercased(), contentID: "authority-c40-bytes",
                byteLength: 128, mediaType: "application/pdf", digests: digestSet,
                byteRole: .immutableOriginal, createdAt: "2026-08-27T00:00:00.000Z"
            ), retrievedAt: fixedDate, recordedAt: fixedDate.addingTimeInterval(1), revision: 1,
            mutationID: fixture.mutationID
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .wrongWorkspace)
        }

        let expired = try QualificationSnapshotV1(
            snapshotID: id(8_440), workspaceID: fixture.workspaceID, declaredScope: "pressure screening",
            issuerDisplay: "Issuer", credentialLocator: "credential-c40",
            effectiveAt: fixedDate.addingTimeInterval(-20), expiresAt: fixedDate.addingTimeInterval(-1),
            provenance: .importedExternalEvidence, capturedAt: fixedDate
        )
        XCTAssertThrowsError(try ApplicabilityContextSnapshotV1(
            snapshotID: id(8_441), workspaceID: fixture.workspaceID,
            siteID: fixture.context.siteID, activityID: id(8_442), workSubjectScope: fixture.scope,
            packageReleases: [], actor: fixture.actor, qualification: expired, effectiveAt: fixedDate,
            basisBindings: fixture.context.basisBindings, disposition: .applicable,
            recordedAt: fixedDate.addingTimeInterval(1), revision: 1, mutationID: fixture.mutationID
        )) { error in
            XCTAssertEqual(error as? PartyAccountabilityFailureV1, .invalidInterval)
        }
    }

    func testV23P03C40ExactMeasurementAndDerivationRetainCanonicalProvenance() throws {
        let fixture = try makeFixture()
        XCTAssertEqual(
            Set(DerivedFactSampleStateV1.allCases), [.present, .missing, .outlier]
        )
        let missingInput = try DerivedFactInputV1(
            sampleID: id(8_530), sampleOrdinal: 2, state: .missing, measurement: nil
        )
        let outlierInput = try DerivedFactInputV1(
            sampleID: id(8_531), sampleOrdinal: 3, state: .outlier, measurement: fixture.measurement
        )
        XCTAssertEqual(missingInput.measurement, nil)
        XCTAssertEqual(outlierInput.measurement?.canonicalValue, fixture.measurement.canonicalValue)
        XCTAssertThrowsError(try DerivedFactInputV1(
            sampleID: id(8_532), sampleOrdinal: 4, state: .missing, measurement: fixture.measurement
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .invalidValue)
        }
        let orderedStates = try DerivedFactProvenanceV1(
            provenanceID: id(8_533), workspaceID: fixture.workspaceID,
            protocolReleaseID: fixture.protocolRelease.releaseID,
            evaluatorDescriptorID: fixture.evaluator.descriptorID,
            inputs: [outlierInput, missingInput, fixture.provenance.inputs[0]],
            result: nil, disposition: .inconclusive,
            recordedAt: fixedDate.addingTimeInterval(2), revision: 1, mutationID: fixture.mutationID
        )
        XCTAssertEqual(orderedStates.inputs.map(\.sampleOrdinal), [1, 2, 3])
        XCTAssertEqual(orderedStates.inputs.map(\.state), [.present, .missing, .outlier])

        XCTAssertNoThrow(try KernelUnitRegistryV1.validateFrozenRegistry())

        let inch = try ExactUnitConverterV1.convert(
            try ExactDecimalV1(mantissa: 1, scale: 0), from: "[in_i]"
        )
        XCTAssertEqual(inch.canonicalValue, try ExactDecimalV1(mantissa: 25_400_000, scale: 9))
        XCTAssertEqual(inch.receipt.disposition, .exact)
        let psi = try ExactUnitConverterV1.convert(
            try ExactDecimalV1(mantissa: 1, scale: 0), from: "psi"
        )
        XCTAssertEqual(psi.canonicalValue, try ExactDecimalV1(mantissa: 6_894_757_293, scale: 9))
        let fahrenheit = try ExactUnitConverterV1.convert(
            try ExactDecimalV1(mantissa: 32, scale: 0), from: "[degF]"
        )
        XCTAssertEqual(fahrenheit.canonicalValue, try ExactDecimalV1(mantissa: 273_150_000, scale: 6))
        XCTAssertEqual(
            try ExactUnitConverterV1.rounded(numerator: 1, denominator: 2, targetScale: 0).receipt.disposition,
            .tieEvenUnchanged
        )
        XCTAssertEqual(
            try ExactUnitConverterV1.rounded(numerator: 3, denominator: 2, targetScale: 0).receipt.disposition,
            .tieEvenAdjusted
        )
        XCTAssertThrowsError(try ExactUnitConverterV1.rounded(
            numerator: Int64.max, denominator: 1, targetScale: 1
        )) { error in
            XCTAssertEqual(error as? ResponseContractFailureV1, .arithmeticOverflow)
        }

        XCTAssertThrowsError(try MeasurementProtocolReleaseV1(
            releaseID: id(8_500), workspaceID: fixture.workspaceID, protocolID: id(8_501),
            designation: "Mismatched dimension", dimension: .length, normativeUnitID: "psi",
            samplingPolicy: .single, minimumSampleCount: 1, maximumSampleCount: 1,
            missingSamplePolicy: .failClosed, outlierPolicy: .retainAll,
            duplicatePolicy: .reject, requiresUncertainty: false, evaluatorDescriptorID: id(8_502),
            recordedAt: fixedDate
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .invalidValue)
        }
        XCTAssertThrowsError(try DerivedFactEvaluatorDescriptorV1(
            descriptorID: id(8_510), workspaceID: fixture.workspaceID, evaluatorID: "ratio",
            evaluatorVersion: "1", implementationSHA256: digest, kind: .ratioPercent,
            inputDimension: .pressure, outputDimension: .length, recordedAt: fixedDate
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .invalidValue)
        }

        let inconclusive = try DerivedFactProvenanceV1(
            provenanceID: id(8_520), workspaceID: fixture.workspaceID,
            protocolReleaseID: fixture.protocolRelease.releaseID,
            evaluatorDescriptorID: fixture.evaluator.descriptorID, inputs: fixture.provenance.inputs,
            result: nil, disposition: .inconclusive, recordedAt: fixedDate.addingTimeInterval(5),
            revision: 1, mutationID: fixture.mutationID
        )
        XCTAssertNil(inconclusive.result)
        XCTAssertEqual(inconclusive.disposition, .inconclusive)

        XCTAssertThrowsError(try DerivedFactProvenanceV1(
            provenanceID: id(8_521), workspaceID: fixture.workspaceID,
            protocolReleaseID: fixture.protocolRelease.releaseID,
            evaluatorDescriptorID: fixture.evaluator.descriptorID,
            inputs: fixture.provenance.inputs + fixture.provenance.inputs,
            result: fixture.measurement, disposition: .evaluated,
            recordedAt: fixedDate.addingTimeInterval(5), revision: 1, mutationID: fixture.mutationID
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .duplicateIdentity)
        }
        XCTAssertThrowsError(try DerivedFactProvenanceV1(
            provenanceID: id(8_522), workspaceID: fixture.workspaceID,
            protocolReleaseID: fixture.protocolRelease.releaseID,
            evaluatorDescriptorID: fixture.evaluator.descriptorID, inputs: fixture.provenance.inputs,
            result: fixture.measurement, disposition: .inconclusive,
            recordedAt: fixedDate.addingTimeInterval(5), revision: 1, mutationID: fixture.mutationID
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .invalidValue)
        }

        let successor = try DerivedFactProvenanceV1(
            provenanceID: id(8_523), workspaceID: fixture.workspaceID,
            protocolReleaseID: fixture.protocolRelease.releaseID,
            evaluatorDescriptorID: fixture.evaluator.descriptorID, inputs: fixture.provenance.inputs,
            result: fixture.measurement, disposition: .evaluated,
            uncertaintyCanonical: try ExactDecimalV1(mantissa: 2, scale: 1),
            predecessorProvenanceID: fixture.provenance.provenanceID,
            recordedAt: fixedDate.addingTimeInterval(6), revision: 2, mutationID: fixture.mutationID
        )
        XCTAssertEqual(successor.predecessorProvenanceID, fixture.provenance.provenanceID)
        XCTAssertEqual(successor.revision, 2)
    }

    func testV23P03C40CanonicalReplayTamperAndAllPersistenceRows() throws {
        let fixture = try makeFixture()
        let receipt = try KernelConformanceFixtureHarnessV1.makeC40Receipt(
            for: fixture.aggregate, workspaceID: fixture.workspaceID
        )
        XCTAssertEqual(receipt.canonicalAggregateSHA256, receipt.replayAggregateSHA256)
        XCTAssertEqual(receipt.sourceCount, 2)
        XCTAssertEqual(receipt.applicabilityCount, 1)
        XCTAssertEqual(receipt.classificationCount, 1)
        XCTAssertEqual(receipt.measurementProtocolCount, 1)
        XCTAssertEqual(receipt.derivedFactCount, 1)
        XCTAssertEqual(receipt.searchFieldIDs, SearchAuthorityCriterionPersistencePolicyV1.fieldIDs)
        XCTAssertEqual(receipt.reportSectionID, ReportAuthorityCriterionProjectionPolicyV1.sectionID)
        XCTAssertEqual(receipt.requiredReportWording, "assessed against")
        XCTAssertTrue(receipt.excludesLicensedSourceBytes)
        XCTAssertTrue(receipt.excludesRawLocators)
        try assertCanonicalRoundTrip(fixture.source)
        try assertCanonicalRoundTrip(fixture.basis)
        try assertCanonicalRoundTrip(fixture.context)
        try assertCanonicalRoundTrip(fixture.assessment)
        try assertCanonicalRoundTrip(fixture.severity)
        try assertCanonicalRoundTrip(fixture.mapping)
        try assertCanonicalRoundTrip(fixture.classification)
        try assertCanonicalRoundTrip(fixture.protocolRelease)
        try assertCanonicalRoundTrip(fixture.evaluator)
        try assertCanonicalRoundTrip(fixture.provenance)
        let firstReplay = try AuthorityCriterionCanonicalCodecV1.encode(fixture.aggregate)
        let replayed = try AuthorityCriterionCanonicalCodecV1.decode(AuthorityCriterionAggregateV1.self, from: firstReplay)
        let secondReplay = try AuthorityCriterionCanonicalCodecV1.encode(replayed)
        XCTAssertEqual(firstReplay, secondReplay)
        XCTAssertEqual(replayed, fixture.aggregate)

        var hostileSource = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: AuthorityCriterionCanonicalCodecV1.encode(fixture.source)
            ) as? [String: Any]
        )
        hostileSource["releaseSHA256"] = String(repeating: "b", count: 64)
        let hostileSourceData = try JSONSerialization.data(withJSONObject: hostileSource, options: [.sortedKeys])
        let decodedHostileSource = try AuthorityCriterionCanonicalCodecV1.decode(
            AuthoritySourceReleaseV1.self, from: hostileSourceData
        )
        XCTAssertThrowsError(try decodedHostileSource.validate()) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .digestMismatch)
        }

        let sourceRow = try AuthoritySourceReleaseRow(fixture.source)
        let basisRow = try RequirementBasisBindingRow(fixture.basis)
        let contextRow = try ApplicabilityContextSnapshotRow(fixture.context)
        let assessmentRow = try AssessmentScopeSnapshotRow(fixture.assessment)
        let severityRow = try SeverityScaleReleaseRow(fixture.severity)
        let classificationRow = try FindingClassificationBindingRow(fixture.classification)
        let protocolRow = try MeasurementProtocolReleaseRow(fixture.protocolRelease)
        let evaluatorRow = try DerivedFactEvaluatorDescriptorRow(fixture.evaluator)
        let provenanceRow = try DerivedFactProvenanceRow(fixture.provenance)
        XCTAssertEqual(try sourceRow.value(), fixture.source)
        XCTAssertEqual(try basisRow.value(), fixture.basis)
        XCTAssertEqual(try contextRow.value(), fixture.context)
        XCTAssertEqual(try assessmentRow.value(), fixture.assessment)
        XCTAssertEqual(try severityRow.value(), fixture.severity)
        XCTAssertEqual(try classificationRow.value(), fixture.classification)
        XCTAssertEqual(try protocolRow.value(), fixture.protocolRelease)
        XCTAssertEqual(try evaluatorRow.value(), fixture.evaluator)
        XCTAssertEqual(try provenanceRow.value(), fixture.provenance)
        XCTAssertEqual(sourceRow.recordedAt, fixture.source.recordedAt)
        XCTAssertEqual(provenanceRow.recordedAt, fixture.provenance.recordedAt)

        let destinationWorkspace = try WorkspaceID(rawValue: id(8_900))
        let reboundContext = try fixture.context.rebound(to: destinationWorkspace)
        XCTAssertEqual(reboundContext.snapshotID, fixture.context.snapshotID)
        XCTAssertEqual(reboundContext.workspaceID, destinationWorkspace)
        XCTAssertEqual(reboundContext.basisBindings.map(\.bindingID), fixture.context.basisBindings.map(\.bindingID))
        XCTAssertNotEqual(reboundContext.snapshotSHA256, fixture.context.snapshotSHA256)
        let reboundSuccessor = try fixture.successorSource.rebound(to: destinationWorkspace)
        XCTAssertEqual(reboundSuccessor.releaseID, fixture.successorSource.releaseID)
        XCTAssertEqual(
            reboundSuccessor.contentLocator?.workspaceID,
            destinationWorkspace.rawValue.uuidString.lowercased()
        )
        XCTAssertNotEqual(reboundSuccessor.releaseSHA256, fixture.successorSource.releaseSHA256)
    }

    func testV23P03C40MutationCoordinatorPredecessorConcurrencyAndReceiptReplay() throws {
        let receipt = try KernelConformanceFixtureHarnessV1.makeC40MutationBoundaryReceipt()
        let appendIdentity = receipt.append.affectedIdentity
        let successorIdentity = receipt.successor.affectedIdentity

        XCTAssertNil(receipt.append.predecessorIdentity)
        XCTAssertEqual(receipt.append.concurrencyIdentity, appendIdentity)
        XCTAssertEqual(receipt.successor.predecessorIdentity, appendIdentity)
        XCTAssertEqual(receipt.successor.concurrencyIdentity, appendIdentity)
        XCTAssertEqual(receipt.successor.affectedIdentity, successorIdentity)
        XCTAssertEqual(receipt.append.mutationReceipt.resultingRevision.entityRevisions.first?.revision, 1)
        XCTAssertEqual(receipt.successor.mutationReceipt.expectedRevision.entityRevisions.first?.revision, 1)
        XCTAssertEqual(receipt.successor.mutationReceipt.resultingRevision.entityRevisions.first?.revision, 2)
        XCTAssertNotEqual(receipt.append.mutationReceipt.mutationID, receipt.successor.mutationReceipt.mutationID)
        XCTAssertNotEqual(receipt.append.mutationSHA256, receipt.successor.mutationSHA256)
        XCTAssertNotEqual(receipt.appendMutationSHA256, receipt.successorMutationSHA256)
        XCTAssertTrue(receipt.appendReplayStable)
        XCTAssertTrue(receipt.successorReplayStable)
        XCTAssertTrue(receipt.coordinatorValidationPassed)
        XCTAssertTrue(receipt.staleAppendRejected)
        XCTAssertTrue(receipt.missingPredecessorRejected)
        XCTAssertTrue(receipt.foreignWorkspaceRejected)

        let appendData = try AuthorityCriterionCanonicalCodecV1.encode(receipt.append)
        XCTAssertEqual(
            try AuthorityCriterionCanonicalCodecV1.decode(
                AuthorityCriterionMutationReceiptV1.self, from: appendData
            ),
            receipt.append
        )
        let successorData = try AuthorityCriterionCanonicalCodecV1.encode(receipt.successor)
        XCTAssertEqual(
            try AuthorityCriterionCanonicalCodecV1.decode(
                AuthorityCriterionMutationReceiptV1.self, from: successorData
            ),
            receipt.successor
        )
    }

    func testV23P03C40DeterministicEvaluatorRejectsHostileInputs() throws {
        let fixture = try makeFixture()
        let evaluator = try DerivedFactEvaluatorDescriptorV1(
            descriptorID: id(8_600), workspaceID: fixture.workspaceID,
            evaluatorID: BundledDerivedFactEvaluatorRegistryV1.evaluatorID(for: .identityCanonical),
            evaluatorVersion: BundledDerivedFactEvaluatorRegistryV1.evaluatorVersion,
            implementationSHA256: try BundledDerivedFactEvaluatorRegistryV1.implementationSHA256(for: .identityCanonical),
            kind: .identityCanonical, inputDimension: .pressure, outputDimension: .pressure,
            recordedAt: fixedDate.addingTimeInterval(30), mutationID: fixture.mutationID
        )
        let protocolRelease = try MeasurementProtocolReleaseV1(
            releaseID: id(8_601), workspaceID: fixture.workspaceID, protocolID: id(8_602),
            designation: "Identity protocol", dimension: .pressure, normativeUnitID: "psi",
            samplingPolicy: .single, minimumSampleCount: 1, maximumSampleCount: 1,
            missingSamplePolicy: .failClosed, outlierPolicy: .retainAll,
            duplicatePolicy: .reject, requiresUncertainty: false,
            evaluatorDescriptorID: evaluator.descriptorID,
            recordedAt: fixedDate.addingTimeInterval(31), mutationID: fixture.mutationID
        )
        let evaluated = try DeterministicDerivedFactEvaluatorV1.evaluate(
            provenanceID: id(8_603), workspaceID: fixture.workspaceID,
            protocolRelease: protocolRelease, evaluator: evaluator,
            inputs: fixture.provenance.inputs,
            recordedAt: fixedDate.addingTimeInterval(32)
        )
        XCTAssertEqual(evaluated.disposition, .evaluated)
        XCTAssertEqual(evaluated.result?.canonicalValue, fixture.measurement.canonicalValue)
        XCTAssertEqual(evaluated.result?.source, .derived)
        XCTAssertEqual(evaluated.inputs, fixture.provenance.inputs)

        let uncertaintyProtocol = try MeasurementProtocolReleaseV1(
            releaseID: id(8_625), workspaceID: fixture.workspaceID, protocolID: id(8_628),
            designation: "Required uncertainty protocol", dimension: .pressure, normativeUnitID: "psi",
            samplingPolicy: .single, minimumSampleCount: 1, maximumSampleCount: 1,
            missingSamplePolicy: .failClosed, outlierPolicy: .retainAll,
            duplicatePolicy: .reject, requiresUncertainty: true,
            evaluatorDescriptorID: evaluator.descriptorID,
            recordedAt: fixedDate.addingTimeInterval(32.5), mutationID: fixture.mutationID
        )
        XCTAssertThrowsError(try DeterministicDerivedFactEvaluatorV1.evaluate(
            provenanceID: id(8_626), workspaceID: fixture.workspaceID,
            protocolRelease: uncertaintyProtocol, evaluator: evaluator,
            inputs: fixture.provenance.inputs,
            recordedAt: fixedDate.addingTimeInterval(32.75)
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .invalidValue)
        }

        let measuredWithUncertainty = try ExactMeasurementV1(
            enteredValue: try ExactDecimalV1(mantissa: 1, scale: 0), enteredUnitID: "psi",
            precisionScale: 0, uncertaintyCanonical: try ExactDecimalV1(mantissa: 1, scale: 1),
            source: .instrumentObserved, captureMethodID: "pressure-meter-uncertainty"
        )
        let completeUncertaintyInput = try DerivedFactInputV1(
            sampleID: id(8_627), sampleOrdinal: 1, measurement: measuredWithUncertainty
        )
        let completeUncertaintyResult = try DeterministicDerivedFactEvaluatorV1.evaluate(
            provenanceID: id(8_629), workspaceID: fixture.workspaceID,
            protocolRelease: uncertaintyProtocol, evaluator: evaluator,
            inputs: [completeUncertaintyInput], recordedAt: fixedDate.addingTimeInterval(33)
        )
        XCTAssertEqual(completeUncertaintyResult.disposition, .evaluated)
        XCTAssertEqual(completeUncertaintyResult.uncertaintyCanonical, measuredWithUncertainty.uncertaintyCanonical)

        let inconclusiveProtocol = try MeasurementProtocolReleaseV1(
            releaseID: id(8_604), workspaceID: fixture.workspaceID, protocolID: id(8_605),
            designation: "Inconclusive protocol", dimension: .pressure, normativeUnitID: "psi",
            samplingPolicy: .orderedSeries, minimumSampleCount: 2, maximumSampleCount: 2,
            missingSamplePolicy: .inconclusive, outlierPolicy: .retainAll,
            duplicatePolicy: .reject, requiresUncertainty: false,
            evaluatorDescriptorID: evaluator.descriptorID,
            recordedAt: fixedDate.addingTimeInterval(33), mutationID: fixture.mutationID
        )
        let inconclusive = try DeterministicDerivedFactEvaluatorV1.evaluate(
            provenanceID: id(8_606), workspaceID: fixture.workspaceID,
            protocolRelease: inconclusiveProtocol, evaluator: evaluator,
            inputs: fixture.provenance.inputs,
            recordedAt: fixedDate.addingTimeInterval(34)
        )
        XCTAssertEqual(inconclusive.disposition, .inconclusive)
        XCTAssertNil(inconclusive.result)

        let strictProtocol = try MeasurementProtocolReleaseV1(
            releaseID: id(8_607), workspaceID: fixture.workspaceID, protocolID: id(8_608),
            designation: "Strict sample protocol", dimension: .pressure, normativeUnitID: "psi",
            samplingPolicy: .orderedSeries, minimumSampleCount: 2, maximumSampleCount: 2,
            missingSamplePolicy: .failClosed, outlierPolicy: .retainAll,
            duplicatePolicy: .reject, requiresUncertainty: false,
            evaluatorDescriptorID: evaluator.descriptorID,
            recordedAt: fixedDate.addingTimeInterval(35), mutationID: fixture.mutationID
        )
        XCTAssertThrowsError(try DeterministicDerivedFactEvaluatorV1.evaluate(
            provenanceID: id(8_609), workspaceID: fixture.workspaceID,
            protocolRelease: strictProtocol, evaluator: evaluator,
            inputs: fixture.provenance.inputs,
            recordedAt: fixedDate.addingTimeInterval(36)
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .insufficientSamples)
        }

        let unknownEvaluator = try DerivedFactEvaluatorDescriptorV1(
            descriptorID: id(8_610), workspaceID: fixture.workspaceID,
            evaluatorID: "com.assetrounds.unknown", evaluatorVersion: "1",
            implementationSHA256: digest, kind: .identityCanonical,
            inputDimension: .pressure, outputDimension: .pressure,
            recordedAt: fixedDate.addingTimeInterval(37), mutationID: fixture.mutationID
        )
        XCTAssertThrowsError(try DeterministicDerivedFactEvaluatorV1.evaluate(
            provenanceID: id(8_611), workspaceID: fixture.workspaceID,
            protocolRelease: protocolRelease, evaluator: unknownEvaluator,
            inputs: fixture.provenance.inputs,
            recordedAt: fixedDate.addingTimeInterval(38)
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .unsupportedEvaluator)
        }

        let lengthMeasurement = try ExactMeasurementV1(
            enteredValue: try ExactDecimalV1(mantissa: 1, scale: 0), enteredUnitID: "m",
            precisionScale: 0, uncertaintyCanonical: nil, source: .instrumentObserved,
            captureMethodID: "length-meter"
        )
        let lengthInput = try DerivedFactInputV1(
            sampleID: id(8_612), sampleOrdinal: 1, measurement: lengthMeasurement
        )
        XCTAssertThrowsError(try DeterministicDerivedFactEvaluatorV1.evaluate(
            provenanceID: id(8_613), workspaceID: fixture.workspaceID,
            protocolRelease: protocolRelease, evaluator: evaluator,
            inputs: [lengthInput], recordedAt: fixedDate.addingTimeInterval(39)
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .dimensionMismatch)
        }

        let duplicateID = try DerivedFactInputV1(
            sampleID: fixture.provenance.inputs[0].sampleID, sampleOrdinal: 2,
            measurement: fixture.measurement
        )
        XCTAssertThrowsError(try DeterministicDerivedFactEvaluatorV1.evaluate(
            provenanceID: id(8_614), workspaceID: fixture.workspaceID,
            protocolRelease: protocolRelease, evaluator: evaluator,
            inputs: [fixture.provenance.inputs[0], duplicateID],
            recordedAt: fixedDate.addingTimeInterval(40)
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .duplicateSample)
        }

        let duplicateValue = try DerivedFactInputV1(
            sampleID: id(8_615), sampleOrdinal: 2, measurement: fixture.measurement
        )
        let duplicateValueProtocol = try MeasurementProtocolReleaseV1(
            releaseID: id(8_616), workspaceID: fixture.workspaceID, protocolID: id(8_617),
            designation: "Duplicate value protocol", dimension: .pressure, normativeUnitID: "psi",
            samplingPolicy: .orderedSeries, minimumSampleCount: 2, maximumSampleCount: 2,
            missingSamplePolicy: .failClosed, outlierPolicy: .retainAll,
            duplicatePolicy: .reject, requiresUncertainty: false,
            evaluatorDescriptorID: evaluator.descriptorID,
            recordedAt: fixedDate.addingTimeInterval(41), mutationID: fixture.mutationID
        )
        XCTAssertThrowsError(try DeterministicDerivedFactEvaluatorV1.evaluate(
            provenanceID: id(8_618), workspaceID: fixture.workspaceID,
            protocolRelease: duplicateValueProtocol, evaluator: evaluator,
            inputs: [fixture.provenance.inputs[0], duplicateValue],
            recordedAt: fixedDate.addingTimeInterval(42)
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .duplicateSample)
        }

        let ratioEvaluator = try DerivedFactEvaluatorDescriptorV1(
            descriptorID: id(8_619), workspaceID: fixture.workspaceID,
            evaluatorID: BundledDerivedFactEvaluatorRegistryV1.evaluatorID(for: .ratioPercent),
            evaluatorVersion: BundledDerivedFactEvaluatorRegistryV1.evaluatorVersion,
            implementationSHA256: try BundledDerivedFactEvaluatorRegistryV1.implementationSHA256(for: .ratioPercent),
            kind: .ratioPercent, inputDimension: .pressure, outputDimension: .dimensionless,
            recordedAt: fixedDate.addingTimeInterval(43), mutationID: fixture.mutationID
        )
        let ratioProtocol = try MeasurementProtocolReleaseV1(
            releaseID: id(8_620), workspaceID: fixture.workspaceID, protocolID: id(8_621),
            designation: "Ratio protocol", dimension: .pressure, normativeUnitID: "psi",
            samplingPolicy: .orderedSeries, minimumSampleCount: 2, maximumSampleCount: 2,
            missingSamplePolicy: .failClosed, outlierPolicy: .retainAll,
            duplicatePolicy: .retainDistinctIdentities, requiresUncertainty: false,
            evaluatorDescriptorID: ratioEvaluator.descriptorID,
            recordedAt: fixedDate.addingTimeInterval(44), mutationID: fixture.mutationID
        )
        let zeroMeasurement = try ExactMeasurementV1(
            enteredValue: try ExactDecimalV1(mantissa: 0, scale: 0), enteredUnitID: "psi",
            precisionScale: 0, uncertaintyCanonical: nil, source: .instrumentObserved,
            captureMethodID: "zero-pressure-meter"
        )
        let zeroInput = try DerivedFactInputV1(
            sampleID: id(8_623), sampleOrdinal: 2, measurement: zeroMeasurement
        )
        let numeratorInput = try DerivedFactInputV1(
            sampleID: id(8_622), sampleOrdinal: 1, measurement: fixture.measurement
        )
        XCTAssertThrowsError(try DeterministicDerivedFactEvaluatorV1.evaluate(
            provenanceID: id(8_624), workspaceID: fixture.workspaceID,
            protocolRelease: ratioProtocol, evaluator: ratioEvaluator,
            inputs: [numeratorInput, zeroInput],
            recordedAt: fixedDate.addingTimeInterval(45)
        )) { error in
            XCTAssertEqual(error as? AuthorityCriterionFailureV1, .arithmeticFailure)
        }
    }

    func testV23P03C40SearchProjectionUsesOnlyBoundedWorkFields() throws {
        let registry = try SearchIndexRebuildCoordinatorV1.makeExtendedRegistry(
            includeAccountability: true, includeAssetSemantics: true, includeAuthorityCriterion: true
        )
        XCTAssertEqual(registry.fields.count, SearchContractLimitsV1.maximumAllProjectionFieldRegistrations)
        for fieldID in SearchAuthorityCriterionPersistencePolicyV1.fieldIDs {
            let field = try registry.descriptor(fieldID: fieldID, sourceKind: .work)
            XCTAssertEqual(field.sourceKind, .work)
            XCTAssertEqual(field.privacyClass, .approvedCustomerText)
            XCTAssertEqual(field.snippetPermission, .boundedUserVisibleExcerpt)
            XCTAssertEqual(field.retention, .untilSourceFieldIsAmended)
            XCTAssertEqual(field.purgeOwner, .indexRebuildCoordinator)
        }

        let source = try SearchSourceRevisionV1(
            workspaceID: id(8_700), generationID: id(8_701), commitRevision: 12
        )
        let index = try SearchIndexRevisionV1(
            workspaceID: source.workspaceID, generationID: source.generationID,
            indexedCommitRevision: source.commitRevision
        )
        let records = try SearchAuthorityCriterionPersistencePolicyV1.fieldIDs.map { fieldID in
            try SearchIndexProjectionRecordV1(
                workspaceID: source.workspaceID, sourceKind: .work,
                sourceStableID: "activity-c40", sourceRevision: source.commitRevision,
                fieldID: fieldID, normalizedTokens: ["recorded"],
                displayIdentity: "Recorded authority criterion", locationBreadcrumb: [],
                status: "RECORDED", permittedSnippet: "Recorded basis", sourceTimestamp: fixedDate
            )
        }
        let projection = try SearchIndexProjectionV1(
            source: source, index: index, records: records, registry: registry
        )
        XCTAssertEqual(projection.records.count, SearchAuthorityCriterionPersistencePolicyV1.fieldIDs.count)
        XCTAssertEqual(projection.records.map(\.fieldID).sorted(), SearchAuthorityCriterionPersistencePolicyV1.fieldIDs.sorted())
        XCTAssertEqual(SearchIndexReconciliationV1.disposition(source: source, index: index), .current)
        XCTAssertEqual(
            SearchIndexReconciliationV1.disposition(
                source: source,
                index: try SearchIndexRevisionV1(
                    workspaceID: source.workspaceID, generationID: source.generationID,
                    indexedCommitRevision: source.commitRevision - 1
                )
            ),
            .staleDropAndRebuild
        )
    }

    func testV23P03C40PortableCorpusRemainsStaticAndProvisional() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = root.appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/AuthorityCriterion/V21P03C40AuthorityCriterionCorpusV1.json"
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        XCTAssertEqual(fixture["schema"] as? String, "V21P03C40AuthorityCriterionCorpusV1")
        XCTAssertEqual(fixture["cardID"] as? String, "V23-P03-C40")
        XCTAssertEqual(
            (fixture["persistence"] as? [String: Any])?["schemaRelease"] as? String,
            "PERSISTENT_SCHEMA_V11_AUTHORITY_CRITERION_DERIVATION"
        )
        let claims = try XCTUnwrap(fixture["claims"] as? [String: Any])
        for key in ["native", "hosted", "adoption", "acceptance", "release", "acceptanceCredit", "releaseCredit"] {
            XCTAssertEqual(claims[key] as? Bool, false, key)
        }
        XCTAssertEqual(
            fixture["requiredContractNames"] as? [String],
            [
                "AuthoritySourceReleaseV1", "LicenseStorageDispositionV1",
                "RequirementBasisBindingV1", "ApplicabilityContextSnapshotV1",
                "ApplicabilityDispositionV1", "AssessmentScopeSnapshotV1",
                "SeverityScaleReleaseV1", "FindingClassificationBindingV1",
                "MeasurementProtocolReleaseV1", "DerivedFactEvaluatorDescriptorV1",
                "DerivedFactProvenanceV1",
            ]
        )
        XCTAssertEqual(
            (fixture["hostileCases"] as? [[String: Any]])?.count,
            16
        )

        let hostileCases = try XCTUnwrap(fixture["hostileCases"] as? [[String: Any]])
        let expectedHostileIDs = [
            "missing-adoption-basis", "contradictory-source-basis", "gps-derived-jurisdiction",
            "copyrighted-bytes", "source-digest-mismatch", "expired-qualification",
            "duplicate-samples", "zero-denominator", "overflow", "dimension-mismatch",
            "display-rounding-boundary", "unknown-evaluator", "unknown-unit-version",
            "floating-point-threshold", "package-script", "safe-compliant-certified-copy-leak",
        ]
        XCTAssertEqual(hostileCases.compactMap { $0["id"] as? String }, expectedHostileIDs)
        XCTAssertTrue(hostileCases.allSatisfy { $0["expectedDisposition"] as? String == "FAIL_CLOSED" })

        let interruptionCases = try XCTUnwrap(fixture["interruptionCases"] as? [[String: Any]])
        XCTAssertEqual(
            interruptionCases.compactMap { $0["id"] as? String },
            [
                "release-admission-boundary", "binding-boundary", "derivation-boundary",
                "report-boundary", "archive-boundary", "restore-boundary", "replay-boundary",
            ]
        )
        XCTAssertTrue(interruptionCases.allSatisfy {
            $0["expectedDisposition"] as? String == "RETRY_IDEMPOTENT_NO_PARTIAL_ACTIVATION"
        })

        let recoveryCases = try XCTUnwrap(fixture["recoveryCases"] as? [[String: Any]])
        XCTAssertEqual(
            recoveryCases.compactMap { $0["id"] as? String },
            [
                "backup-clone-fork", "journal-replay-checkpoint", "compatibility-forward-fix",
                "search-report", "delete-erase", "released-v1",
            ]
        )
        XCTAssertTrue(recoveryCases.allSatisfy {
            $0["expectedDisposition"] as? String == "RECOVER_EFFECT_RECEIPT_AND_HISTORY"
        })
    }
}

extension V9_25AuthorityCriterionDerivationTests {
    func testV23P03C13AuthorityLaneUsesTypedMutationAndCanonicalVisibility() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_925)
        let mutation = try EvidenceAssuranceMutationV1(
            workspaceID: fixture.workspaceID,
            expectedRevision: 0,
            mutationID: fixture.routineVisibility.mutationID,
            postImage: .appendVisibility(fixture.routineVisibility)
        )

        try mutation.validate()
        XCTAssertEqual(try mutation.affectedIdentity.kind, .evidenceVisibility)
        XCTAssertEqual(try mutation.affectedIdentity.id, fixture.routineVisibility.visibilityID)
        XCTAssertEqual(try mutation.concurrencyIdentity, try mutation.affectedIdentity)
        XCTAssertEqual(try mutation.canonicalData(), try mutation.canonicalData())
        XCTAssertEqual(fixture.routineVisibility.visibilitySHA256.count, 64)
    }
}

private extension V9_25AuthorityCriterionDerivationTests {
    struct Fixture {
        let workspaceID: WorkspaceID
        let mutationID: MutationIDV1
        let actor: ActorSnapshotV1
        let package: PackageReleaseIdentityV1
        let scope: WorkSubjectScopeSnapshotV1
        let source: AuthoritySourceReleaseV1
        let successorSource: AuthoritySourceReleaseV1
        let basis: RequirementBasisBindingV1
        let qualification: QualificationSnapshotV1
        let context: ApplicabilityContextSnapshotV1
        let assessment: AssessmentScopeSnapshotV1
        let severity: SeverityScaleReleaseV1
        let successorSeverity: SeverityScaleReleaseV1
        let mapping: SeverityScaleMappingReleaseV1
        let classification: FindingClassificationBindingV1
        let measurement: ExactMeasurementV1
        let protocolRelease: MeasurementProtocolReleaseV1
        let evaluator: DerivedFactEvaluatorDescriptorV1
        let provenance: DerivedFactProvenanceV1
        let aggregate: AuthorityCriterionAggregateV1
    }

    func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    func makeFixture() throws -> Fixture {
        let workspaceID = try WorkspaceID(rawValue: id(8_000))
        let mutationID = try MutationIDV1(rawValue: id(8_001))
        let localActor = try LocalActorReferenceV1(
            actorReferenceID: id(8_002), workspaceID: workspaceID, displayName: "C40 Recorder"
        )
        let actor = try ActorSnapshotV1(
            snapshotID: id(8_003), workspaceID: workspaceID, actor: localActor,
            responsibility: .recordedBy, displayNameAtTime: "C40 Recorder", capturedAt: fixedDate
        )
        let package = try PackageReleaseIdentityV1(
            packageID: "com.field-evidence.c40", schemaVersion: 3, contentVersion: 1
        )
        let siteID = id(8_004)
        let semanticCatalog = try makeSemanticCatalog(
            packageRelease: package, releaseID: id(8_006), releasedAt: fixedDate
        )
        let semanticBinding = try WorkSubjectSemanticBindingSnapshotV1(
            assetID: id(8_007), kindBindingEventID: id(8_008), kindBindingRevision: 1,
            catalogRelease: semanticCatalog.reference, semanticID: "asset.kind.authority",
            workflowPackageReleases: [package]
        )
        let scope = try WorkSubjectScopeSnapshotV1(
            snapshotID: id(8_005), workspaceID: workspaceID, siteID: siteID,
            subjects: [WorkSubjectReferenceV1(kind: .asset, subjectID: id(8_007), revision: 1, ownerAssetID: nil)],
            semanticBindings: [semanticBinding], workspaceRevision: 8,
            recordedAt: fixedDate.addingTimeInterval(1)
        )
        let source = try AuthoritySourceReleaseV1(
            releaseID: id(8_010), workspaceID: workspaceID, sourceID: id(8_011),
            sourceType: .adoptedRule, designation: "Field authority rule",
            editionOrRevision: "2024", publisherDisplay: "Recorded publisher",
            publicationAt: fixedDate.addingTimeInterval(-10),
            effectiveFrom: fixedDate.addingTimeInterval(-5), effectiveUntil: fixedDate.addingTimeInterval(100),
            addenda: "Addendum A", sourceURL: "https://authority.example/c40/2024",
            retrievedAt: fixedDate, sourceDigestSHA256: digest,
            licenseStorageDisposition: .metadataAndLocatorOnly,
            recordedAt: fixedDate.addingTimeInterval(1), revision: 1, mutationID: mutationID
        )
        let successorSource = try AuthoritySourceReleaseV1(
            releaseID: id(8_012), workspaceID: workspaceID, sourceID: source.sourceID,
            sourceType: .adoptedRule, designation: source.designation,
            editionOrRevision: "2026", publisherDisplay: source.publisherDisplay,
            publicationAt: fixedDate.addingTimeInterval(2), effectiveFrom: fixedDate.addingTimeInterval(3),
            sourceURL: "https://authority.example/c40/2026", retrievedAt: fixedDate.addingTimeInterval(3),
            sourceDigestSHA256: digest, licenseStorageDisposition: .externalLocatorOnly,
            contentLocator: try ContentLocatorV1(
                locatorID: "authority-c40-locator", workspaceID: workspaceID.rawValue.uuidString.lowercased(),
                contentID: "authority-c40-metadata", locatorRevision: 1,
                contentDigest: try ContentDigestV1(algorithm: .sha256, hexadecimalValue: digest),
                expectedByteLength: 128
            ), supersedesReleaseID: source.releaseID,
            recordedAt: fixedDate.addingTimeInterval(4), revision: 2, mutationID: mutationID
        )
        let basis = try RequirementBasisBindingV1(
            bindingID: id(8_020), workspaceID: workspaceID, basisKind: .adoptedRequirement,
            authorityReleaseID: source.releaseID, criterionID: "criterion.pressure.range",
            clauseLocator: "section-4.2", selectedBy: actor, selectedAt: fixedDate.addingTimeInterval(2),
            revision: 1, mutationID: mutationID
        )
        let qualification = try QualificationSnapshotV1(
            snapshotID: id(8_021), workspaceID: workspaceID, declaredScope: "pressure screening",
            issuerDisplay: "Recorded issuer", credentialLocator: "qualification-c40",
            effectiveAt: fixedDate.addingTimeInterval(-5), expiresAt: fixedDate.addingTimeInterval(100),
            provenance: .importedExternalEvidence, capturedAt: fixedDate.addingTimeInterval(2)
        )
        let context = try ApplicabilityContextSnapshotV1(
            snapshotID: id(8_022), workspaceID: workspaceID, siteID: siteID,
            activityID: id(8_023), workSubjectScope: scope, packageReleases: [package], actor: actor,
            qualification: qualification, effectiveAt: fixedDate.addingTimeInterval(5),
            basisBindings: [basis], disposition: .applicable,
            recordedAt: fixedDate.addingTimeInterval(6), revision: 1, mutationID: mutationID
        )
        let assessment = try AssessmentScopeSnapshotV1(
            snapshotID: id(8_024), workspaceID: workspaceID,
            applicabilityContextID: context.snapshotID, workSubjectScope: scope,
            includedCriterionIDs: ["criterion.screening", basis.criterionID],
            excludedCriterionReasons: ["criterion.deferred": "Not selected for this activity"],
            recordedAt: fixedDate.addingTimeInterval(7), revision: 1, mutationID: mutationID
        )
        let severity = try SeverityScaleReleaseV1(
            releaseID: id(8_030), workspaceID: workspaceID, scaleID: id(8_031),
            designation: "Source severity", levels: [
                try SeverityLevelDefinitionV1(
                    levelID: "minor", localizedLabelKey: "authority.criterion.severity.minor",
                    descriptionKey: "authority.criterion.severity.minor.description"
                ),
                try SeverityLevelDefinitionV1(
                    levelID: "major", localizedLabelKey: "authority.criterion.severity.major",
                    descriptionKey: "authority.criterion.severity.major.description"
                ),
            ], recordedAt: fixedDate.addingTimeInterval(8), revision: 1, mutationID: mutationID
        )
        let successorSeverity = try SeverityScaleReleaseV1(
            releaseID: id(8_032), workspaceID: workspaceID, scaleID: id(8_033),
            designation: "Package severity", levels: [
                try SeverityLevelDefinitionV1(
                    levelID: "low", localizedLabelKey: "authority.criterion.severity.low",
                    descriptionKey: "authority.criterion.severity.low.description"
                ),
                try SeverityLevelDefinitionV1(
                    levelID: "high", localizedLabelKey: "authority.criterion.severity.high",
                    descriptionKey: "authority.criterion.severity.high.description"
                ),
            ], recordedAt: fixedDate.addingTimeInterval(9), revision: 1, mutationID: mutationID
        )
        let mapping = try SeverityScaleMappingReleaseV1(
            releaseID: id(8_034), workspaceID: workspaceID,
            sourceScaleReleaseID: severity.releaseID, destinationScaleReleaseID: successorSeverity.releaseID,
            entries: [
                try SeverityScaleMappingEntryV1(sourceLevelID: "major", destinationLevelID: "high"),
                try SeverityScaleMappingEntryV1(sourceLevelID: "minor", destinationLevelID: "low"),
            ], recordedAt: fixedDate.addingTimeInterval(10), revision: 1, mutationID: mutationID
        )
        let classification = try FindingClassificationBindingV1(
            bindingID: id(8_040), workspaceID: workspaceID, findingID: id(8_041),
            criterionID: basis.criterionID, result: .meetsScreeningCriterion,
            severityScaleReleaseID: severity.releaseID, severityLevelID: "major",
            applicabilityContextID: context.snapshotID, assessmentScopeID: assessment.snapshotID,
            recordedAt: fixedDate.addingTimeInterval(11), revision: 1, mutationID: mutationID
        )
        let measurement = try ExactMeasurementV1(
            enteredValue: try ExactDecimalV1(mantissa: 1, scale: 0), enteredUnitID: "psi",
            precisionScale: 0, uncertaintyCanonical: nil, source: .instrumentObserved,
            captureMethodID: "pressure-meter"
        )
        let evaluator = try DerivedFactEvaluatorDescriptorV1(
            descriptorID: id(8_050), workspaceID: workspaceID, evaluatorID: "pressure.identity",
            evaluatorVersion: "1.0.0", implementationSHA256: digest,
            kind: .identityCanonical, inputDimension: .pressure, outputDimension: .pressure,
            recordedAt: fixedDate.addingTimeInterval(12), mutationID: mutationID
        )
        let protocolRelease = try MeasurementProtocolReleaseV1(
            releaseID: id(8_051), workspaceID: workspaceID, protocolID: id(8_052),
            designation: "Pressure protocol", dimension: .pressure, normativeUnitID: "psi",
            samplingPolicy: .orderedSeries, minimumSampleCount: 1, maximumSampleCount: 4,
            missingSamplePolicy: .failClosed, outlierPolicy: .retainAll,
            duplicatePolicy: .reject, requiresUncertainty: true,
            evaluatorDescriptorID: evaluator.descriptorID, recordedAt: fixedDate.addingTimeInterval(13),
            mutationID: mutationID
        )
        let provenance = try DerivedFactProvenanceV1(
            provenanceID: id(8_053), workspaceID: workspaceID,
            protocolReleaseID: protocolRelease.releaseID, evaluatorDescriptorID: evaluator.descriptorID,
            inputs: [try DerivedFactInputV1(sampleID: id(8_054), measurement: measurement)],
            result: measurement, disposition: .evaluated,
            uncertaintyCanonical: try ExactDecimalV1(mantissa: 1, scale: 1),
            recordedAt: fixedDate.addingTimeInterval(14), revision: 1, mutationID: mutationID
        )
        let aggregate = AuthorityCriterionAggregateV1(
            sourceReleases: [source, successorSource], basisBindings: [basis],
            applicabilityContexts: [context], assessmentScopes: [assessment],
            severityScaleReleases: [severity, successorSeverity], severityMappingReleases: [mapping],
            classificationBindings: [classification], measurementProtocolReleases: [protocolRelease],
            evaluatorDescriptors: [evaluator], derivedFacts: [provenance]
        )
        return Fixture(
            workspaceID: workspaceID, mutationID: mutationID, actor: actor, package: package,
            scope: scope, source: source, successorSource: successorSource, basis: basis,
            qualification: qualification, context: context, assessment: assessment, severity: severity,
            successorSeverity: successorSeverity, mapping: mapping, classification: classification,
            measurement: measurement, protocolRelease: protocolRelease, evaluator: evaluator,
            provenance: provenance, aggregate: aggregate
        )
    }

    func assertCanonicalRoundTrip<T: Codable & Equatable>(
        _ value: T, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let data = try AuthorityCriterionCanonicalCodecV1.encode(value)
        let decoded = try AuthorityCriterionCanonicalCodecV1.decode(T.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
        XCTAssertEqual(try AuthorityCriterionCanonicalCodecV1.encode(decoded), data, file: file, line: line)
    }

    func makeSemanticCatalog(
        packageRelease: PackageReleaseIdentityV1, releaseID: UUID, releasedAt: Date
    ) throws -> AssetSemanticCatalogReleaseV1 {
        try AssetSemanticCatalogReleaseV1(
            releaseID: releaseID,
            packageRelease: packageRelease,
            revision: 1,
            definitions: [try AssetKindDefinitionV1(
                semanticID: "asset.kind.authority",
                displayNameLocalizationKey: "asset.semantic.kind",
                descriptionLocalizationKey: "asset.semantic.heading",
                capabilityIDs: [try AssetSemanticCapabilityIDV1("capability.inspect")],
                compatibleWorkflowPackageReleases: [packageRelease],
                compatibilityPolicy: .sameSemanticIDSuccessor
            )],
            releasedAt: releasedAt
        )
    }
}

extension V9_25AuthorityCriterionDerivationTests {
    func testV23P03C14AuthorityReviewSubjectIsExplicitlyBound() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_225)
        XCTAssertEqual(fixture.subject.kind, .completedActivitySnapshot)
        XCTAssertEqual(fixture.subject.subjectRevision, 1)
        XCTAssertEqual(fixture.subject.subjectSHA256.count, 64)
        XCTAssertEqual(fixture.policy.verifierRule, .differentActorAndPartyRequired)
    }

    func testV23P03DerivedSeriesUsesBoundedProtocolAndProvenance() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        try fixture.protocolRelease.validate()
        try fixture.evaluator.validate()
        try fixture.series.validateClosure(
            captures: [fixture.capture, fixture.secondCapture],
            protocolRelease: fixture.protocolRelease
        )
        XCTAssertEqual(fixture.protocolRelease.samplingPolicy, .orderedSeries)
        XCTAssertEqual(fixture.series.aggregationPolicy, .mean)
        XCTAssertNotNil(fixture.series.derivedFact)
    }
}

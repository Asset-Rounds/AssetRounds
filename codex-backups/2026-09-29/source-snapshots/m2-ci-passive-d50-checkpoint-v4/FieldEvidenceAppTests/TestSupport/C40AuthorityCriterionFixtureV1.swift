import Foundation
@testable import FieldEvidenceApp

/// Existing C40 pure domain fixture, shared without changing its constructors.
enum C40AuthorityCriterionFixtureV1 {
    static let digest = String(repeating: "a", count: 64)
    static let fixedDate = Date(timeIntervalSince1970: 1_735_689_600.125)

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

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    static func makeFixture() throws -> Fixture {
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

    static func makeSemanticCatalog(
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

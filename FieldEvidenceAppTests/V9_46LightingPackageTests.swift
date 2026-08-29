import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C31LightingTestError: Error {
    case interrupted
    case invalidFixture
}

private enum C31LightingTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c3100000-0000-4000-8000-%012x", slot))!
    }

    static func digest(_ character: Character = "a") -> String {
        String(repeating: String(character), count: 64)
    }

    static func workspace() -> WorkspaceID {
        WorkspaceID(rawValue: id(1))
    }

    static func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(10_000 + slot))
    }

    static func actor(
        workspaceID: WorkspaceID,
        slot: Int,
        responsibility: ResponsibilityKindV1 = .recordedBy
    ) throws -> ActorSnapshotV1 {
        let local = try LocalActorReferenceV1(
            actorReferenceID: id(20_000 + slot),
            workspaceID: workspaceID,
            displayName: "C31 local recorder"
        )
        return try ActorSnapshotV1(
            snapshotID: id(30_000 + slot),
            workspaceID: workspaceID,
            actor: local,
            responsibility: responsibility,
            displayNameAtTime: local.displayName,
            capturedAt: fixedDate
        )
    }

    static func packageReference() throws -> LightingPackageReleaseReferenceV1 {
        let data = Data(
            """
            {"packageReleaseID":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","packageID":"c31.lighting","contentVersion":1,"packageSHA256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","workflowSHA256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}
            """.utf8
        )
        let value = try JSONDecoder().decode(LightingPackageReleaseReferenceV1.self, from: data)
        try value.validate()
        return value
    }

    static func packageIdentity() throws -> PackageReleaseIdentityV1 {
        try PackageReleaseIdentityV1(
            packageID: "c31.lighting",
            schemaVersion: 1,
            contentVersion: 1
        )
    }

    static func semanticBinding(
        assetID: UUID,
        package: PackageReleaseIdentityV1,
        semanticID: String = "luminaire.exterior",
        catalogReleaseID: UUID = id(70)
    ) throws -> WorkSubjectSemanticBindingSnapshotV1 {
        let catalog = AssetSemanticCatalogReleaseReferenceV1(
            releaseID: catalogReleaseID,
            packageRelease: package,
            catalogSHA256: digest("d")
        )
        return try WorkSubjectSemanticBindingSnapshotV1(
            assetID: assetID,
            kindBindingEventID: id(71),
            kindBindingRevision: 1,
            catalogRelease: catalog,
            semanticID: semanticID,
            workflowPackageReleases: [package]
        )
    }

    static func relationshipDescriptor(
        workspaceID: WorkspaceID,
        package: PackageReleaseIdentityV1
    ) throws -> FunctionalRelationshipTypeDescriptorV1 {
        let sourceCatalog = AssetSemanticCatalogReleaseReferenceV1(
            releaseID: id(122), packageRelease: package, catalogSHA256: digest("d")
        )
        let targetCatalog = AssetSemanticCatalogReleaseReferenceV1(
            releaseID: id(70), packageRelease: package, catalogSHA256: digest("d")
        )
        return try FunctionalRelationshipTypeDescriptorV1(
            descriptorReleaseID: id(121),
            workspaceID: workspaceID,
            packageRelease: package,
            semanticID: "support.assembly",
            sourceCatalogRelease: sourceCatalog,
            targetCatalogRelease: targetCatalog,
            sourceSemanticIDs: ["support.assembly"],
            targetSemanticIDs: ["luminaire.exterior"],
            direction: .directed,
            symmetry: .asymmetric,
            sourceCardinality: try FunctionalRelationshipCardinalityV1(minimum: 0, maximum: 2),
            targetCardinality: try FunctionalRelationshipCardinalityV1(minimum: 0, maximum: 1),
            selfEdgePolicy: .forbidden,
            cyclePolicy: .forbidden,
            maximumTraversalDepth: 8,
            maximumHardEdges: 4,
            sitePolicy: .sameSiteRequired,
            minimumCardinalityBoundaries: [],
            displayNameLocalizationKey: "lighting.relationship.support.name",
            descriptionLocalizationKey: "lighting.relationship.support.description",
            sourceRoleLocalizationKey: "lighting.relationship.support.source",
            targetRoleLocalizationKey: "lighting.relationship.support.target",
            releasedAt: fixedDate,
            mutationID: try mutation(60)
        )
    }

    static func relationshipEvent(
        eventID: UUID,
        relationshipID: UUID,
        workspaceID: WorkspaceID,
        sourceAssetID: UUID,
        targetAssetID: UUID,
        descriptor: FunctionalRelationshipTypeDescriptorV1,
        mutationSlot: Int,
        recordedAt: Date
    ) throws -> AssetFunctionalRelationshipEventV1 {
        let actor = try LocalActorReferenceV1(
            actorReferenceID: id(5_000 + mutationSlot),
            workspaceID: workspaceID,
            displayName: "C31 relationship recorder"
        )
        return try AssetFunctionalRelationshipEventV1(
            eventID: eventID,
            relationshipID: relationshipID,
            workspaceID: workspaceID,
            action: .added,
            sourceAssetID: sourceAssetID,
            targetAssetID: targetAssetID,
            sourceAssetRevision: 1,
            targetAssetRevision: 1,
            descriptor: FunctionalRelationshipDescriptorReferenceV1(descriptor),
            effectiveAt: fixedDate,
            recordedAt: recordedAt,
            actor: actor,
            provenance: "C31_SUPPORT_RELATIONSHIP",
            expectedRelationshipRevision: 0,
            revision: 1,
            mutationID: try mutation(mutationSlot)
        )
    }

    static func system(
        workspaceID: WorkspaceID,
        duplicateAsset: Bool = false
    ) throws -> LightingSystemV1 {
        let packageReference = try packageReference()
        let package = try packageIdentity()
        let relationshipDescriptor = try relationshipDescriptor(
            workspaceID: workspaceID,
            package: package
        )
        let supportSemanticBinding = try semanticBinding(
            assetID: id(150),
            package: package,
            semanticID: "support.assembly",
            catalogReleaseID: relationshipDescriptor.sourceCatalogRelease.releaseID
        )
        let zoneOne = LightingZoneV1(
            zoneID: id(100),
            displayName: "North parking",
            workSubject: WorkSubjectReferenceV1(
                kind: .locationNode,
                subjectID: id(100),
                revision: 1,
                ownerAssetID: nil
            ),
            declaredActivityClass: "PARKING",
            declaredSecurityClass: "GENERAL"
        )
        let zoneTwo = LightingZoneV1(
            zoneID: id(101),
            displayName: "South walkway",
            workSubject: WorkSubjectReferenceV1(
                kind: .locationNode,
                subjectID: id(101),
                revision: 1,
                ownerAssetID: nil
            ),
            declaredActivityClass: "WALKWAY",
            declaredSecurityClass: "GENERAL"
        )
        let controlOneID = id(110)
        let controlTwoID = id(111)
        let controlOne = ControlGroupV1(
            controlGroupID: controlOneID,
            semanticID: "parking.primary",
            expectation: try ControlExpectationV1(
                controlGroupID: controlOneID.uuidString.lowercased(),
                expectedState: .expectedOperating,
                policyID: "C31_LOCAL_CONTROL_POLICY",
                policyVersion: 1,
                policySHA256: digest("e")
            )
        )
        let controlTwo = ControlGroupV1(
            controlGroupID: controlTwoID,
            semanticID: "walkway.primary",
            expectation: try ControlExpectationV1(
                controlGroupID: controlTwoID.uuidString.lowercased(),
                expectedState: .noExpectation,
                policyID: "C31_LOCAL_CONTROL_POLICY",
                policyVersion: 1,
                policySHA256: digest("e")
            )
        )
        let firstSupportRelationship = FrozenFunctionalRelationshipReferenceV1(
            relationshipID: id(120),
            relationshipRevision: 1,
            descriptorReleaseID: relationshipDescriptor.descriptorReleaseID,
            descriptorReleaseRevision: relationshipDescriptor.revision,
            packageRelease: package,
            semanticCatalogRelease: relationshipDescriptor.sourceCatalogRelease,
            semanticID: relationshipDescriptor.semanticID
        )
        let secondSupportRelationship = FrozenFunctionalRelationshipReferenceV1(
            relationshipID: id(123),
            relationshipRevision: 1,
            descriptorReleaseID: relationshipDescriptor.descriptorReleaseID,
            descriptorReleaseRevision: relationshipDescriptor.revision,
            packageRelease: package,
            semanticCatalogRelease: relationshipDescriptor.sourceCatalogRelease,
            semanticID: relationshipDescriptor.semanticID
        )
        let firstAssetID = id(130)
        let secondAssetID = duplicateAsset ? firstAssetID : id(131)
        let first = LuminaireAssetV1(
            luminaireID: id(140),
            assetID: firstAssetID,
            assetRevision: 1,
            semanticBinding: try semanticBinding(assetID: firstAssetID, package: package),
            zoneIDs: [zoneOne.zoneID, zoneTwo.zoneID],
            controlGroupIDs: [controlOneID],
            supportAssemblyAssetID: id(150),
            supportAssemblySemanticBinding: supportSemanticBinding,
            supportRelationship: firstSupportRelationship,
            supportRelationshipEventID: id(124),
            maintenanceDisposition: .subordinate
        )
        let second = LuminaireAssetV1(
            luminaireID: id(141),
            assetID: secondAssetID,
            assetRevision: 1,
            semanticBinding: try semanticBinding(assetID: secondAssetID, package: package),
            zoneIDs: [zoneTwo.zoneID],
            controlGroupIDs: [controlOneID, controlTwoID],
            supportAssemblyAssetID: id(150),
            supportAssemblySemanticBinding: supportSemanticBinding,
            supportRelationship: secondSupportRelationship,
            supportRelationshipEventID: id(125),
            maintenanceDisposition: .subordinate
        )
        return try LightingSystemV1(
            recordID: id(160),
            systemID: id(161),
            workspaceID: workspaceID,
            siteID: id(162),
            packageRelease: packageReference,
            zones: [zoneTwo, zoneOne],
            controlGroups: [controlTwo, controlOne],
            luminaires: [second, first],
            revision: 1,
            mutationID: try mutation(1),
            recordedBy: try actor(workspaceID: workspaceID, slot: 1),
            recordedAt: fixedDate.addingTimeInterval(3)
        )
    }

    static func topologyAdmission(
        for system: LightingSystemV1
    ) throws -> LightingTopologyAdmissionClosureV1 {
        guard let firstRelationship = system.luminaires.first?.supportRelationship else {
            throw C31LightingTestError.invalidFixture
        }
        let descriptor = try relationshipDescriptor(
            workspaceID: system.workspaceID,
            package: firstRelationship.packageRelease
        )
        let events = try system.luminaires.enumerated().map { offset, luminaire
            -> AssetFunctionalRelationshipEventV1 in
            guard let relationship = luminaire.supportRelationship,
                  let supportID = luminaire.supportAssemblyAssetID,
                  let eventID = luminaire.supportRelationshipEventID else {
                throw C31LightingTestError.invalidFixture
            }
            return try relationshipEvent(
                eventID: eventID,
                relationshipID: relationship.relationshipID,
                workspaceID: system.workspaceID,
                sourceAssetID: supportID,
                targetAssetID: luminaire.assetID,
                descriptor: descriptor,
                mutationSlot: 100 + offset,
                recordedAt: fixedDate.addingTimeInterval(Double(offset + 1))
            )
        }
        return LightingTopologyAdmissionClosureV1(
            descriptors: [descriptor],
            relationshipEvents: events.sorted {
                ($0.relationshipID.uuidString, $0.revision)
                    < ($1.relationshipID.uuidString, $1.revision)
            }
        )
    }

    static func binding(
        plan: MeasurementPlanV1,
        capture: MeasurementCaptureV1
    ) throws -> LightingMeasurementCaptureBindingV1 {
        guard let point = plan.points.first else {
            throw C31LightingTestError.invalidFixture
        }
        return try LightingMeasurementCaptureBindingV1(
            pointID: point.pointID,
            sampleOrdinal: point.ordinal,
            captureID: capture.captureID,
            captureRevision: capture.revision,
            captureSHA256: capture.captureSHA256
        )
    }

    static func rewrittenRelationshipEvent(
        _ event: AssetFunctionalRelationshipEventV1,
        eventID: UUID? = nil,
        sourceAssetID: UUID,
        targetAssetID: UUID,
        mutationSlot: Int
    ) throws -> AssetFunctionalRelationshipEventV1 {
        try relationshipEvent(
            eventID: eventID ?? event.eventID,
            relationshipID: event.relationshipID,
            workspaceID: event.workspaceID,
            sourceAssetID: sourceAssetID,
            targetAssetID: targetAssetID,
            descriptor: try relationshipDescriptor(
                workspaceID: event.workspaceID,
                package: event.descriptor.packageRelease
            ),
            mutationSlot: mutationSlot,
            recordedAt: event.recordedAt
        )
    }

    static func evidenceContext(
        workspaceID: WorkspaceID,
        assetID: UUID,
        note: String = "C31_PHOTO_OR_EXIF_IS_NOT_A_METER"
    ) throws -> EvidenceContextV1 {
        let temporal = try TemporalContextV1(
            occurredAtUTC: fixedDate,
            recordedAtUTC: fixedDate.addingTimeInterval(1),
            localDate: "2027-01-15",
            localTime: "05:30:00",
            utcOffsetSeconds: 0,
            ianaTimeZoneIdentifier: "UTC",
            localTimeDisposition: .unambiguous
        )
        return try EvidenceContextV1(
            contextID: id(200),
            workspaceID: workspaceID,
            evidenceID: "c31-photo-original",
            evidenceSHA256: digest("f"),
            evidenceRevision: 1,
            assetID: assetID,
            assetRevision: 1,
            temporalContext: temporal,
            userObserved: UserObservedEvidenceContextV1(
                condition: .night,
                observationNoteCode: note
            ),
            derivedSolar: nil,
            controlExpectation: nil,
            predecessor: nil,
            revision: 1,
            mutationID: try mutation(2),
            recordedBy: try actor(workspaceID: workspaceID, slot: 2),
            recordedAt: fixedDate.addingTimeInterval(2)
        )
    }

    static func observation(
        system: LightingSystemV1,
        workspaceID: WorkspaceID,
        issueKinds: [LightingIssueKindV1] = [.cameraBandingOnly],
        recordID: UUID = id(210),
        observationID: UUID = id(211),
        predecessor: LightingObservationV1? = nil,
        revision: UInt64 = 1,
        mutationSlot: Int = 3,
        luminaireIndex: Int = 0
    ) throws -> LightingObservationV1 {
        guard system.luminaires.indices.contains(luminaireIndex) else {
            throw C31LightingTestError.invalidFixture
        }
        let luminaire = system.luminaires[luminaireIndex]
        guard let zoneID = luminaire.zoneIDs.first,
              let controlID = luminaire.controlGroupIDs.first else {
            throw C31LightingTestError.invalidFixture
        }
        return try LightingObservationV1(
            recordID: recordID,
            observationID: observationID,
            workspaceID: workspaceID,
            system: system,
            luminaireID: luminaire.luminaireID,
            zoneID: zoneID,
            controlGroupID: controlID,
            evidenceContext: try evidenceContext(workspaceID: workspaceID, assetID: luminaire.assetID),
            observationBasis: try ObservationBasisV1(
                kind: .directlyObserved,
                method: try ObservationMethodV1(key: "c31.photo_or_manual_observation"),
                source: try ObservationSourceReferenceV1(kind: .observer),
                limitations: ["PHOTO_AND_EXIF_NEVER_PROVE_LUX_OR_COMPLIANCE"]
            ),
            issueKinds: issueKinds,
            predecessor: predecessor,
            revision: revision,
            mutationID: try mutation(mutationSlot),
            recordedBy: try actor(workspaceID: workspaceID, slot: 3),
            recordedAt: fixedDate.addingTimeInterval(Double(4 + revision))
        )
    }

    static func plan(
        system: LightingSystemV1,
        protocolRelease: MeasurementProtocolReleaseV1? = nil,
        predecessor: MeasurementPlanV1? = nil,
        revision: UInt64 = 1,
        mutationSlot: Int = 4
    ) throws -> MeasurementPlanV1 {
        let releaseReference: MeasurementProtocolReferenceV1
        if let protocolRelease {
            releaseReference = try MeasurementProtocolReferenceV1(protocolRelease)
        } else {
            releaseReference = try MeasurementProtocolReferenceV1(
                releaseID: id(220),
                revision: 1,
                releaseSHA256: digest("g")
            )
        }
        guard let zoneID = system.zones.first?.zoneID else {
            throw C31LightingTestError.invalidFixture
        }
        let point = LightingMeasurementPointV1(
            pointID: id(221),
            ordinal: 1,
            zoneID: zoneID,
            pageID: id(222),
            spatialFrameID: id(223),
            plane: .horizontal,
            heightMillimetres: 1_000,
            orientationMilliDegrees: 0
        )
        return try MeasurementPlanV1(
            recordID: predecessor.map { _ in id(225) } ?? id(224),
            planID: id(226),
            workspaceID: system.workspaceID,
            system: system,
            planRevision: PlanRevisionReferenceV1(
                planRevisionID: id(227),
                planDocumentID: id(228),
                revision: 1,
                revisionSHA256: digest("h")
            ),
            protocolReference: releaseReference,
            points: [point],
            expectedSampleCount: 1,
            environmentBasisSHA256: digest("i"),
            controlContextSHA256: digest("j"),
            predecessor: predecessor,
            revision: revision,
            mutationID: try mutation(mutationSlot),
            recordedBy: try actor(workspaceID: system.workspaceID, slot: 4),
            recordedAt: fixedDate.addingTimeInterval(10 + Double(revision))
        )
    }

    static func claim(
        observation: LightingObservationReferenceV1,
        workspaceID: WorkspaceID,
        subjectAssetID: UUID,
        tier: LightingClaimTierV1,
        plan: MeasurementPlanV1? = nil,
        captureID: UUID? = nil,
        recordID: UUID = id(230),
        predecessor: LightingClaimStateV1? = nil,
        revision: UInt64 = 1,
        mutationSlot: Int = 5
    ) throws -> LightingClaimStateV1 {
        let measurement = try plan.map {
            guard let captureID else {
                throw C31LightingTestError.invalidFixture
            }
            try LightingMeasurementClaimReferenceV1(
                planID: $0.planID,
                planRevision: $0.revision,
                planSHA256: $0.planSHA256,
                captureIDs: [captureID],
                seriesID: nil,
                seriesRevision: nil,
                seriesSHA256: nil
            )
        }
        return try LightingClaimStateV1(
            recordID: recordID,
            claimID: predecessor?.claimID ?? id(231),
            workspaceID: workspaceID,
            subjectAssetID: subjectAssetID,
            tier: tier,
            observation: observation,
            measurement: measurement,
            predecessor: predecessor,
            revision: revision,
            mutationID: try mutation(mutationSlot),
            reviewedBy: try actor(workspaceID: workspaceID, slot: 5, responsibility: .reviewedBy),
            recordedAt: fixedDate.addingTimeInterval(12 + Double(revision))
        )
    }

    static func finding() throws -> FindingV1 {
        try FindingV1(
            findingID: "c31-finding-visible",
            revision: 1,
            severity: try FindingSeverityBindingV1(
                severityID: "low",
                severityScaleReleaseID: "c31-scale",
                severityScaleSHA256: digest("k")
            ),
            categoryID: "lighting",
            subject: try FindingSubjectV1(
                subjectKindID: "luminaire",
                subjectID: "c31-luminaire",
                subjectRevision: 1
            ),
            source: try FindingSourceV1(
                kind: .humanObservation,
                sourceID: "c31-observation",
                sourceRevision: 1
            ),
            summary: "Visible potential lighting issue"
        )
    }
}

private struct C31LightingHostileCase: Decodable {
    let id: String
    let category: String
    let expected: String
}

private struct C31LightingCorpus: Decodable {
    let schema: String
    let schemaVersion: Int
    let cardID: String
    let persistentSchemaVersion: Int
    let recordsSchemaVersion: Int
    let durableFamilies: [String]
    let durableFamilyCount: Int
    let claimTiers: [String]
    let measurementBoundaries: [String]
    let lifecycleDimensions: [String]
    let exclusions: [String]
    let hostileCases: [C31LightingHostileCase]
    let backupClosureVectors: [String]
}

@MainActor
final class V9_46LightingPackageTests: XCTestCase {
    private func loadCorpus() throws -> C31LightingCorpus {
        let bundle = Bundle(for: V9_46LightingPackageTests.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V22P03C31LightingPackageCorpusV1",
                withExtension: "json",
                subdirectory: "Lighting"
            )
        )
        return try JSONDecoder().decode(C31LightingCorpus.self, from: Data(contentsOf: url))
    }

    func testV23P03C31G01LightingTopologyObservationAndMeasurementBoundariesAreExact() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.schema, "V22P03C31LightingPackageCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P03-C31")
        XCTAssertEqual(corpus.persistentSchemaVersion, LightingPersistenceEnrollmentV1.persistentSchemaVersion)
        XCTAssertEqual(corpus.recordsSchemaVersion, LightingPersistenceEnrollmentV1.recordsSchemaVersion)
        XCTAssertEqual(corpus.durableFamilyCount, LightingPersistenceEnrollmentV1.durableModelCount)
        XCTAssertEqual(corpus.durableFamilies.count, 5)
        XCTAssertEqual(Set(corpus.claimTiers), Set(LightingClaimTierV1.allCases.map(\.rawValue)))

        let measurementFixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let system = try C31LightingTestSupport.system(workspaceID: measurementFixture.workspace)
        try system.validateIntrinsic()
        XCTAssertEqual(system.luminaires.count, 2)
        XCTAssertEqual(Set(system.luminaires.map(\.assetID)).count, 2)
        XCTAssertEqual(system.luminaires.filter { $0.zoneIDs.count > 1 }.count, 1)
        XCTAssertEqual(
            Set(system.luminaires.compactMap(\.supportAssemblyAssetID)).count,
            1,
            "shared support remains one referenced assembly, not cloned per head"
        )

        let observation = try C31LightingTestSupport.observation(
            system: system,
            workspaceID: measurementFixture.workspace
        )
        let observationReference = try LightingObservationReferenceV1(observation)
        let plan = try C31LightingTestSupport.plan(
            system: system,
            protocolRelease: measurementFixture.protocolRelease
        )
        let binding = try C31LightingTestSupport.binding(
            plan: plan,
            capture: measurementFixture.capture
        )
        try plan.validateCompleteCaptures(
            [measurementFixture.capture],
            bindings: [binding],
            protocolRelease: measurementFixture.protocolRelease,
            instrument: measurementFixture.instrument,
            calibration: measurementFixture.currentCalibration,
            quality: [measurementFixture.qualityClear]
        )
        let topologyAdmission = try C31LightingTestSupport.topologyAdmission(for: system)
        try LightingTopologyAdmissionV1.validate(system, admission: topologyAdmission)
        XCTAssertEqual(observation.observationBasis.kind, .directlyObserved)
        XCTAssertTrue(observation.observationBasis.limitations.contains("PHOTO_AND_EXIF_NEVER_PROVE_LUX_OR_COMPLIANCE"))

        let observedClaim = try C31LightingTestSupport.claim(
            observation: observationReference,
            workspaceID: measurementFixture.workspace,
            subjectAssetID: observation.assetID,
            tier: .observed
        )
        try observedClaim.validateIntrinsic()
        XCTAssertEqual(observedClaim.tier, .observed)

        let converted = try ExactUnitConverterV1.convert(
            try ExactDecimalV1(mantissa: 1, scale: 0),
            from: "[fc_i]"
        )
        XCTAssertEqual(converted.canonicalValue, try ExactDecimalV1(mantissa: 1_076_391, scale: 5))
        let alreadyLux = try ExactUnitConverterV1.convert(
            try ExactDecimalV1(mantissa: 1_076_391, scale: 5),
            from: "lx"
        )
        XCTAssertEqual(alreadyLux.canonicalValue, try ExactDecimalV1(mantissa: 1_076_391, scale: 5))
        XCTAssertEqual(converted.canonicalValue, alreadyLux.canonicalValue)
        XCTAssertEqual(converted.canonicalUnitID, alreadyLux.canonicalUnitID)

        let encoded = try LightingCanonicalCodecV1.encode(system)
        let decoded = try LightingCanonicalCodecV1.decode(LightingSystemV1.self, from: encoded)
        XCTAssertEqual(decoded, system)
        let reordered = try LightingSystemV1(
            recordID: system.recordID,
            systemID: system.systemID,
            workspaceID: system.workspaceID,
            siteID: system.siteID,
            packageRelease: system.packageRelease,
            zones: system.zones.reversed(),
            controlGroups: system.controlGroups.reversed(),
            luminaires: system.luminaires.reversed(),
            revision: system.revision,
            mutationID: system.mutationID,
            recordedBy: system.recordedBy,
            recordedAt: system.recordedAt
        )
        XCTAssertEqual(try LightingCanonicalCodecV1.encode(reordered), encoded)
        XCTAssertEqual(plan.protocolReference.releaseID, measurementFixture.protocolRelease.releaseID)
    }

    func testV23P03C31A01SharedSupportsMultiHeadAndMultiAreaTopologyWithoutClones() throws {
        let measurementFixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let system = try C31LightingTestSupport.system(workspaceID: measurementFixture.workspace)
        let first = try XCTUnwrap(system.luminaires.first)
        XCTAssertGreaterThan(first.zoneIDs.count, 1)
        XCTAssertEqual(
            Set(system.luminaires.compactMap(\.supportAssemblyAssetID)),
            Set([C31LightingTestSupport.id(150)])
        )
        XCTAssertEqual(Set(system.luminaires.flatMap(\.zoneIDs)).count, 2)
        XCTAssertEqual(Set(system.luminaires.flatMap(\.controlGroupIDs)).count, 2)
        XCTAssertTrue(system.controlGroups.contains { $0.expectation.expectedState == .noExpectation })

        let observation = try C31LightingTestSupport.observation(
            system: system,
            workspaceID: measurementFixture.workspace,
            issueKinds: [.cameraBandingOnly, .controlUnknown, .partialOutput]
        )
        XCTAssertEqual(
            observation.issueKinds,
            [.cameraBandingOnly, .controlUnknown, .partialOutput].sorted()
        )
        let observationReference = try LightingObservationReferenceV1(observation)
        let plan = try C31LightingTestSupport.plan(system: system)
        let measuredClaim = try C31LightingTestSupport.claim(
            observation: observationReference,
            workspaceID: measurementFixture.workspace,
            subjectAssetID: observation.assetID,
            tier: .measured,
            plan: plan,
            captureID: C31LightingTestSupport.id(40)
        )
        XCTAssertEqual(measuredClaim.tier, .measured)
        try measuredClaim.validateIntrinsic()
        XCTAssertThrowsError(
            try C31LightingTestSupport.claim(
                observation: observationReference,
                workspaceID: measurementFixture.workspace,
                subjectAssetID: observation.assetID,
                tier: .measured
            )
        )

        XCTAssertThrowsError(
            try C31LightingTestSupport.system(
                workspaceID: measurementFixture.workspace,
                duplicateAsset: true
            )
        )
    }

    func testV23P03C31H01ForbiddenClaimsInvalidMeasurementsAndUnsafeWorkFailClosed() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.hostileCases.count, 45)
        XCTAssertEqual(Set(corpus.hostileCases.map(\.id)).count, 45)
        XCTAssertTrue(corpus.hostileCases.allSatisfy { $0.expected == "REJECTED" })
        XCTAssertEqual(corpus.backupClosureVectors, [
            "MISSING_C19_CAPTURE", "MISMATCHED_C19_CAPTURE",
            "MISSING_C19_PROTOCOL", "MISMATCHED_C19_PROTOCOL",
            "MISSING_C19_INSTRUMENT", "MISMATCHED_C19_INSTRUMENT",
            "MISSING_C19_CALIBRATION", "MISMATCHED_C19_CALIBRATION",
            "MISSING_C19_QUALITY", "MISMATCHED_C19_QUALITY",
            "MISSING_C40_PROVENANCE", "MISMATCHED_C40_PROVENANCE",
            "DUPLICATE_SEMANTIC_KEY_ARCHIVE"
        ])
        let IDs = Set(corpus.hostileCases.map(\.id))
        for required in [
            "CERTIFICATE_EXPIRED", "CERTIFICATE_HASH_MISMATCH", "UNCERTAINTY_MISSING",
            "SPECTRAL_CONCERN", "COSINE_RESPONSE_CONCERN", "TEMPERATURE_CONCERN",
            "NAN_VALUE", "NEGATIVE_VALUE", "OUT_OF_RANGE_VALUE", "ROUNDING_CROSSES_CRITERION",
            "DUPLICATE_SAMPLE", "MIXED_PLAN_VERSION", "MIXED_PLANE_OR_HEIGHT",
            "WRONG_CRITERION_EDITION", "WRONG_CRITERION_JURISDICTION", "CAMERA_BANDING_ONLY",
            "UNKNOWN_CONTROL_EXPECTATION", "WHOLE_ZONE_OUTAGE", "WRONG_ISSUE_CLOSE",
            "SAFETY_STOP_ELECTRICAL_OR_TRAFFIC"
        ] {
            XCTAssertTrue(IDs.contains(required), "hostile matrix lost \(required)")
        }

        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let system = try C31LightingTestSupport.system(workspaceID: fixture.workspace)
        let topologyAdmission = try C31LightingTestSupport.topologyAdmission(for: system)
        let firstEvent = try XCTUnwrap(topologyAdmission.relationshipEvents.first)
        let firstLuminaire = try XCTUnwrap(system.luminaires.first)
        let supportAssetID = try XCTUnwrap(firstLuminaire.supportAssemblyAssetID)

        var wrongTargetEvents = topologyAdmission.relationshipEvents
        wrongTargetEvents[0] = try C31LightingTestSupport.rewrittenRelationshipEvent(
            firstEvent,
            sourceAssetID: supportAssetID,
            targetAssetID: C31LightingTestSupport.id(399),
            mutationSlot: 401
        )
        XCTAssertThrowsError(
            try LightingTopologyAdmissionV1.validate(
                system,
                admission: LightingTopologyAdmissionClosureV1(
                    descriptors: topologyAdmission.descriptors,
                    relationshipEvents: wrongTargetEvents
                )
            )
        ) { error in
            XCTAssertEqual(error as? LightingContractFailureV1, .staleReference)
        }

        var reversedEvents = topologyAdmission.relationshipEvents
        reversedEvents[0] = try C31LightingTestSupport.rewrittenRelationshipEvent(
            firstEvent,
            sourceAssetID: firstLuminaire.assetID,
            targetAssetID: supportAssetID,
            mutationSlot: 402
        )
        XCTAssertThrowsError(
            try LightingTopologyAdmissionV1.validate(
                system,
                admission: LightingTopologyAdmissionClosureV1(
                    descriptors: topologyAdmission.descriptors,
                    relationshipEvents: reversedEvents
                )
            )
        ) { error in
            XCTAssertEqual(error as? LightingContractFailureV1, .staleReference)
        }

        var staleEvents = topologyAdmission.relationshipEvents
        staleEvents[0] = try C31LightingTestSupport.rewrittenRelationshipEvent(
            firstEvent,
            eventID: C31LightingTestSupport.id(403),
            sourceAssetID: supportAssetID,
            targetAssetID: firstLuminaire.assetID,
            mutationSlot: 403
        )
        XCTAssertThrowsError(
            try LightingTopologyAdmissionV1.validate(
                system,
                admission: LightingTopologyAdmissionClosureV1(
                    descriptors: topologyAdmission.descriptors,
                    relationshipEvents: staleEvents
                )
            )
        ) { error in
            XCTAssertEqual(error as? LightingContractFailureV1, .staleReference)
        }

        XCTAssertThrowsError(try LightingLimitsV1.digest("not-a-certificate-digest"))
        XCTAssertThrowsError(
            try LightingLimitsV1.instant(Date(timeIntervalSinceReferenceDate: Double.nan))
        )
        XCTAssertThrowsError(
            try LightingMeasurementPointV1(
                pointID: C31LightingTestSupport.id(300),
                ordinal: 1,
                zoneID: C31LightingTestSupport.id(301),
                pageID: C31LightingTestSupport.id(302),
                spatialFrameID: C31LightingTestSupport.id(303),
                plane: .horizontal,
                heightMillimetres: -1,
                orientationMilliDegrees: 0
            ).validate()
        )
        XCTAssertThrowsError(
            try LightingMeasurementPointV1(
                pointID: C31LightingTestSupport.id(304),
                ordinal: 1,
                zoneID: C31LightingTestSupport.id(305),
                pageID: C31LightingTestSupport.id(306),
                spatialFrameID: C31LightingTestSupport.id(307),
                plane: .horizontal,
                heightMillimetres: 1_000,
                orientationMilliDegrees: 400_000
            ).validate()
        )

        let partialPlan = try C31LightingTestSupport.plan(system: system)
        let partialBinding = try C31LightingTestSupport.binding(
            plan: partialPlan,
            capture: fixture.capture
        )
        XCTAssertThrowsError(
            try partialPlan.validateCompleteCaptures(
                [], bindings: [], protocolRelease: fixture.protocolRelease,
                instrument: fixture.instrument,
                calibration: fixture.currentCalibration,
                quality: []
            )
        )
        XCTAssertThrowsError(
            try partialPlan.validateCompleteCaptures(
                [fixture.capture, fixture.capture], bindings: [partialBinding, partialBinding],
                protocolRelease: fixture.protocolRelease, instrument: fixture.instrument,
                calibration: fixture.currentCalibration,
                quality: [fixture.qualityClear, fixture.qualityClear]
            )
        )
        let manualBinding = try C31LightingTestSupport.binding(
            plan: partialPlan,
            capture: fixture.manualCapture
        )
        XCTAssertThrowsError(
            try partialPlan.validateCompleteCaptures(
                [fixture.manualCapture], bindings: [manualBinding],
                protocolRelease: fixture.protocolRelease, instrument: fixture.instrument,
                calibration: fixture.currentCalibration,
                quality: [fixture.qualityClear]
            )
        )

        let observation = try C31LightingTestSupport.observation(
            system: system,
            workspaceID: fixture.workspace,
            issueKinds: [.appearedUnlit, .visiblePotentialElectricalIndicator]
        )
        let observationReference = try LightingObservationReferenceV1(observation)
        XCTAssertThrowsError(
            try C31LightingTestSupport.claim(
                observation: observationReference,
                workspaceID: fixture.workspace,
                subjectAssetID: observation.assetID,
                tier: .measured
            )
        )
        let finding = try C31LightingTestSupport.finding()
        let openIssue = try LightingIssueV1(
            recordID: C31LightingTestSupport.id(320),
            issueID: C31LightingTestSupport.id(321),
            workspaceID: fixture.workspace,
            kind: .appearedUnlit,
            subjectAssetID: observation.assetID,
            observation: observationReference,
            finding: finding,
            disposition: .open,
            revision: 1,
            mutationID: try C31LightingTestSupport.mutation(6),
            recordedBy: try C31LightingTestSupport.actor(workspaceID: fixture.workspace, slot: 6),
            recordedAt: C31LightingTestSupport.fixedDate.addingTimeInterval(20)
        )
        try openIssue.validateIntrinsic()
        let validIssueOperation = LightingWriteOperationV1.appendIssue(
            value: openIssue,
            predecessor: nil,
            admission: LightingIssueAdmissionClosureV1(observation: observation)
        )
        try validIssueOperation.validate()

        let foreignWorkspace = WorkspaceID(rawValue: C31LightingTestSupport.id(410))
        let foreignSystem = try C31LightingTestSupport.system(workspaceID: foreignWorkspace)
        let foreignObservation = try C31LightingTestSupport.observation(
            system: foreignSystem,
            workspaceID: foreignWorkspace,
            issueKinds: [.appearedUnlit],
            recordID: C31LightingTestSupport.id(411),
            observationID: C31LightingTestSupport.id(412),
            mutationSlot: 411
        )
        XCTAssertThrowsError(
            try LightingWriteOperationV1.appendIssue(
                value: openIssue,
                predecessor: nil,
                admission: LightingIssueAdmissionClosureV1(observation: foreignObservation)
            ).validate()
        ) { error in
            XCTAssertEqual(error as? LightingContractFailureV1, .staleReference)
        }

        let subjectObservation = try C31LightingTestSupport.observation(
            system: system,
            workspaceID: fixture.workspace,
            issueKinds: [.appearedUnlit],
            recordID: C31LightingTestSupport.id(413),
            observationID: C31LightingTestSupport.id(414),
            mutationSlot: 413,
            luminaireIndex: 1
        )
        XCTAssertThrowsError(
            try LightingWriteOperationV1.appendIssue(
                value: openIssue,
                predecessor: nil,
                admission: LightingIssueAdmissionClosureV1(observation: subjectObservation)
            ).validate()
        ) { error in
            XCTAssertEqual(error as? LightingContractFailureV1, .staleReference)
        }

        let contentObservation = try C31LightingTestSupport.observation(
            system: system,
            workspaceID: fixture.workspace,
            issueKinds: [.appearedUnlit, .partialOutput],
            recordID: C31LightingTestSupport.id(210),
            observationID: C31LightingTestSupport.id(211),
            mutationSlot: 415
        )
        XCTAssertThrowsError(
            try LightingWriteOperationV1.appendIssue(
                value: openIssue,
                predecessor: nil,
                admission: LightingIssueAdmissionClosureV1(observation: contentObservation)
            ).validate()
        ) { error in
            XCTAssertEqual(error as? LightingContractFailureV1, .staleReference)
        }

        let validPlan = try C31LightingTestSupport.plan(
            system: system,
            protocolRelease: fixture.protocolRelease
        )
        let validBinding = try C31LightingTestSupport.binding(
            plan: validPlan,
            capture: fixture.capture
        )
        let measuredClaim = try C31LightingTestSupport.claim(
            observation: observationReference,
            workspaceID: fixture.workspace,
            subjectAssetID: observation.assetID,
            tier: .measured,
            plan: validPlan,
            captureID: fixture.capture.captureID,
            recordID: C31LightingTestSupport.id(420),
            mutationSlot: 420
        )
        let validClaimOperation = LightingWriteOperationV1.appendClaim(
            value: measuredClaim,
            predecessor: nil,
            admission: .measured(
                observation: observation,
                plan: validPlan,
                protocolRelease: fixture.protocolRelease,
                captures: [fixture.capture],
                bindings: [validBinding],
                instrument: fixture.instrument,
                calibration: fixture.currentCalibration,
                quality: [fixture.qualityClear]
            )
        )
        try validClaimOperation.validate()
        XCTAssertThrowsError(
            try LightingWriteOperationV1.appendClaim(
                value: measuredClaim,
                predecessor: nil,
                admission: .observed(observation: observation)
            ).validate()
        ) { error in
            XCTAssertEqual(error as? LightingContractFailureV1, .forbiddenClaim)
        }

        let forgedClaim = try C31LightingTestSupport.claim(
            observation: observationReference,
            workspaceID: fixture.workspace,
            subjectAssetID: observation.assetID,
            tier: .measured,
            plan: validPlan,
            captureID: C31LightingTestSupport.id(421),
            recordID: C31LightingTestSupport.id(422),
            mutationSlot: 422
        )
        XCTAssertThrowsError(
            try LightingWriteOperationV1.appendClaim(
                value: forgedClaim,
                predecessor: nil,
                admission: .measured(
                    observation: observation,
                    plan: validPlan,
                    protocolRelease: fixture.protocolRelease,
                    captures: [fixture.capture],
                    bindings: [validBinding],
                    instrument: fixture.instrument,
                    calibration: fixture.currentCalibration,
                    quality: [fixture.qualityClear]
                )
            ).validate()
        ) { error in
            XCTAssertEqual(error as? LightingContractFailureV1, .forbiddenClaim)
        }

        let calibrationExpiry = try XCTUnwrap(fixture.currentCalibration.expiresAt)
        let lateCapture = try MeasurementCaptureV1(
            captureID: C31LightingTestSupport.id(430),
            workspaceID: fixture.workspace,
            packageReleaseID: fixture.capture.packageReleaseID,
            workflowSHA256: fixture.capture.workflowSHA256,
            response: fixture.capture.response,
            measurement: fixture.capture.measurement,
            sourceMode: fixture.capture.sourceMode,
            instrument: fixture.capture.instrument,
            calibration: fixture.capture.calibration,
            observationBasis: fixture.capture.observationBasis,
            operatorSnapshot: fixture.capture.operatorSnapshot,
            evidence: fixture.capture.evidence,
            capturedAt: calibrationExpiry.addingTimeInterval(1),
            mutationID: try C31LightingTestSupport.mutation(430)
        )
        let lateBinding = try C31LightingTestSupport.binding(
            plan: partialPlan,
            capture: lateCapture
        )
        let lateQuality = try MeasurementQualityEvaluatorV1.assessCapture(
            assessmentID: C31LightingTestSupport.id(431),
            capture: lateCapture,
            calibration: fixture.currentCalibration,
            requiresUncertainty: fixture.protocolRelease.requiresUncertainty,
            policyVersion: "C31-LIGHTING-POLICY-V1",
            policySHA256: C31LightingTestSupport.digest("e"),
            assessedAt: lateCapture.capturedAt,
            mutationID: try C31LightingTestSupport.mutation(431)
        )
        XCTAssertThrowsError(
            try partialPlan.validateCompleteCaptures(
                [lateCapture],
                bindings: [lateBinding],
                protocolRelease: fixture.protocolRelease,
                instrument: fixture.instrument,
                calibration: fixture.currentCalibration,
                quality: [lateQuality]
            )
        ) { error in
            XCTAssertEqual(error as? LightingContractFailureV1, .incompleteMeasurementPlan)
        }

        let wrongProtocol = try MeasurementProtocolReleaseV1(
            releaseID: C31LightingTestSupport.id(432),
            workspaceID: fixture.workspace,
            protocolID: C31LightingTestSupport.id(433),
            designation: "C31 wrong unit protocol",
            dimension: .illuminance,
            normativeUnitID: "[fc_i]",
            samplingPolicy: .single,
            minimumSampleCount: 1,
            maximumSampleCount: 1,
            missingSamplePolicy: .failClosed,
            outlierPolicy: .retainAll,
            duplicatePolicy: .reject,
            requiresUncertainty: false,
            evaluatorDescriptorID: fixture.evaluator.descriptorID,
            recordedAt: fixture.protocolRelease.recordedAt,
            mutationID: try C31LightingTestSupport.mutation(432)
        )
        let wrongProtocolPlan = try C31LightingTestSupport.plan(
            system: system,
            protocolRelease: wrongProtocol
        )
        let wrongProtocolBinding = try C31LightingTestSupport.binding(
            plan: wrongProtocolPlan,
            capture: fixture.capture
        )
        XCTAssertThrowsError(
            try wrongProtocolPlan.validateCompleteCaptures(
                [fixture.capture],
                bindings: [wrongProtocolBinding],
                protocolRelease: wrongProtocol,
                instrument: fixture.instrument,
                calibration: fixture.currentCalibration,
                quality: [fixture.qualityClear]
            )
        ) { error in
            XCTAssertEqual(error as? LightingContractFailureV1, .incompleteMeasurementPlan)
        }

        XCTAssertThrowsError(
            try LightingIssueV1(
                recordID: C31LightingTestSupport.id(322),
                issueID: C31LightingTestSupport.id(323),
                workspaceID: fixture.workspace,
                kind: .appearedUnlit,
                subjectAssetID: observation.assetID,
                observation: observationReference,
                finding: finding,
                disposition: .resolved,
                resolutionEvidence: [],
                revision: 1,
                mutationID: try C31LightingTestSupport.mutation(7),
                recordedBy: try C31LightingTestSupport.actor(workspaceID: fixture.workspace, slot: 7),
                recordedAt: C31LightingTestSupport.fixedDate.addingTimeInterval(20)
            )
        )

        let unsafe = LightingSafetyAuthorityV1(
            siteAuthoritySHA256: nil,
            applicableControlPlanSHA256: nil,
            energizedWorkAuthorized: false,
            trafficControlAuthorized: false
        )
        try LightingSafetyGateV1.requireAllowed(.observeFromAuthorizedPosition, authority: unsafe)
        XCTAssertThrowsError(try LightingSafetyGateV1.requireAllowed(.openEquipment, authority: unsafe))
        XCTAssertThrowsError(try LightingSafetyGateV1.requireAllowed(.repair, authority: unsafe))
        XCTAssertThrowsError(try LightingSafetyGateV1.requireAllowed(.enterActiveTraffic, authority: unsafe))
        XCTAssertEqual(openIssue.disposition, .open)
    }

    func testV23P03C31I01InterruptedLightingMutationRecoversAsZeroOrOneCanonicalSuccess() async throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let system = try C31LightingTestSupport.system(workspaceID: fixture.workspace)
        let operation = LightingWriteOperationV1.appendSystem(
            value: system,
            predecessor: nil,
            admission: try C31LightingTestSupport.topologyAdmission(for: system)
        )
        try operation.validate()
        let firstDigest = try LightingCanonicalCodecV1.sha256(operation)
        let secondDigest = try LightingCanonicalCodecV1.sha256(operation)
        XCTAssertEqual(firstDigest, secondDigest)
        XCTAssertEqual(operation.expectedRevision, 0)
        XCTAssertEqual(operation.revision, 1)
        XCTAssertEqual(try operation.affectedIdentity.kind, .lightingSystem)

        let writer = C31InterruptedLightingWriter()
        let adapter = LightingLifecycleAdapterV1(writer: writer)
        do {
            _ = try await adapter.commit(operation)
            XCTFail("an interruption before the receipt cannot report success")
        } catch {
            XCTAssertTrue(error is C31LightingTestError)
        }
        XCTAssertEqual(writer.attempts, 1, "one canonical writer attempt, no second store")
        try operation.validate()
        XCTAssertEqual(writer.recordedOperationDigests, [firstDigest])
    }

    func testV23P03C31R01RestoreReplayAndHistoricLightingReportsRemainExact() throws {
        let corpus = try loadCorpus()
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let system = try C31LightingTestSupport.system(workspaceID: fixture.workspace)
        let observation = try C31LightingTestSupport.observation(
            system: system,
            workspaceID: fixture.workspace,
            issueKinds: [.appearedUnlit]
        )
        let observationReference = try LightingObservationReferenceV1(observation)
        let plan = try C31LightingTestSupport.plan(
            system: system,
            protocolRelease: fixture.protocolRelease
        )
        let observedClaim = try C31LightingTestSupport.claim(
            observation: observationReference,
            workspaceID: fixture.workspace,
            subjectAssetID: observation.assetID,
            tier: .observed
        )
        let measuredClaim = try C31LightingTestSupport.claim(
            observation: observationReference,
            workspaceID: fixture.workspace,
            subjectAssetID: observation.assetID,
            tier: .measured,
            plan: plan,
            captureID: fixture.capture.captureID,
            recordID: C31LightingTestSupport.id(232),
            predecessor: observedClaim,
            revision: 2,
            mutationSlot: 8
        )
        try measuredClaim.validateSuccessor(of: observedClaim)

        let systemRow = try LightingSystemRow(system)
        let observationRow = try LightingObservationRow(observation)
        let planRow = try MeasurementPlanRow(plan)
        let claimRow = try LightingClaimStateRow(measuredClaim)
        XCTAssertEqual(try systemRow.value(), system)
        XCTAssertEqual(try observationRow.value(), observation)
        XCTAssertEqual(try planRow.value(), plan)
        XCTAssertEqual(try claimRow.value(), measuredClaim)
        XCTAssertEqual(
            try LightingCanonicalCodecV1.encode(try claimRow.value()),
            try LightingCanonicalCodecV1.encode(measuredClaim)
        )

        // A lighting claim is not a self-contained measurement.  The package,
        // import, and restore paths must retain the exact C19 capture graph and
        // the C40 authority/provenance row that makes the protocol resolvable.
        let captureBinding = try C31LightingTestSupport.binding(
            plan: plan,
            capture: fixture.capture
        )
        try LightingClaimAdmissionV1.validateMeasured(
            measuredClaim,
            observation: observation,
            plan: plan,
            captures: [fixture.capture],
            bindings: [captureBinding],
            protocolRelease: fixture.protocolRelease,
            instrument: fixture.instrument,
            calibration: fixture.currentCalibration,
            quality: [fixture.qualityClear]
        )

        func lightingRecord(
            _ kind: V31BackupLightingRecordV1.Kind,
            id: UUID,
            revision: UInt64,
            canonicalData: Data
        ) -> V31BackupLightingRecordV1 {
            V31BackupLightingRecordV1(
                kind: kind,
                id: id,
                workspaceID: fixture.workspace.rawValue,
                revision: revision,
                canonicalData: canonicalData
            )
        }
        let lightingRows = try [
            lightingRecord(
                .lightingSystem,
                id: system.recordID,
                revision: system.revision,
                canonicalData: LightingCanonicalCodecV1.encode(system)
            ),
            lightingRecord(
                .lightingObservation,
                id: observation.recordID,
                revision: observation.revision,
                canonicalData: LightingCanonicalCodecV1.encode(observation)
            ),
            lightingRecord(
                .measurementPlan,
                id: plan.recordID,
                revision: plan.revision,
                canonicalData: LightingCanonicalCodecV1.encode(plan)
            ),
            lightingRecord(
                .lightingClaim,
                id: observedClaim.recordID,
                revision: observedClaim.revision,
                canonicalData: LightingCanonicalCodecV1.encode(observedClaim)
            ),
            lightingRecord(
                .lightingClaim,
                id: measuredClaim.recordID,
                revision: measuredClaim.revision,
                canonicalData: LightingCanonicalCodecV1.encode(measuredClaim)
            )
        ].sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }

        func measurementRecord(
            _ kind: V18BackupMeasurementIntegrityRecordV1.Kind,
            id: UUID,
            revision: UInt64,
            canonicalData: Data
        ) -> V18BackupMeasurementIntegrityRecordV1 {
            V18BackupMeasurementIntegrityRecordV1(
                kind: kind,
                id: id,
                workspaceID: fixture.workspace.rawValue,
                revision: revision,
                canonicalData: canonicalData
            )
        }
        let completeMeasurementRows = try [
            measurementRecord(
                .instrumentReference,
                id: fixture.instrument.referenceID,
                revision: fixture.instrument.revision,
                canonicalData: MeasurementIntegrityCanonicalCodecV1.encode(fixture.instrument)
            ),
            measurementRecord(
                .calibrationSnapshot,
                id: fixture.currentCalibration.snapshotID,
                revision: fixture.currentCalibration.revision,
                canonicalData: MeasurementIntegrityCanonicalCodecV1.encode(fixture.currentCalibration)
            ),
            measurementRecord(
                .measurementCapture,
                id: fixture.capture.captureID,
                revision: fixture.capture.revision,
                canonicalData: MeasurementIntegrityCanonicalCodecV1.encode(fixture.capture)
            ),
            measurementRecord(
                .measurementCapture,
                id: fixture.secondCapture.captureID,
                revision: fixture.secondCapture.revision,
                canonicalData: MeasurementIntegrityCanonicalCodecV1.encode(fixture.secondCapture)
            ),
            measurementRecord(
                .measurementSeries,
                id: fixture.openSeries.snapshotID,
                revision: fixture.openSeries.revision,
                canonicalData: MeasurementIntegrityCanonicalCodecV1.encode(fixture.openSeries)
            ),
            measurementRecord(
                .measurementSeries,
                id: fixture.series.snapshotID,
                revision: fixture.series.revision,
                canonicalData: MeasurementIntegrityCanonicalCodecV1.encode(fixture.series)
            ),
            measurementRecord(
                .qualityAssessment,
                id: fixture.qualityClear.assessmentID,
                revision: fixture.qualityClear.revision,
                canonicalData: MeasurementIntegrityCanonicalCodecV1.encode(fixture.qualityClear)
            )
        ].sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
        let protocolRow = V11BackupAuthorityCriterionRecordV1(
            kind: .measurementProtocolRelease,
            id: fixture.protocolRelease.releaseID,
            workspaceID: fixture.workspace.rawValue,
            canonicalData: try AuthorityCriterionCanonicalCodecV1.encode(fixture.protocolRelease)
        )
        let measurementManifest = V4BackupManifestV1(
            backupSchemaVersion: 1,
            consumedEvaluationRootIDs: [],
            declaredPayloadByteCount: 0,
            entries: [],
            exportedAt: C31LightingTestSupport.fixedDate,
            packs: [],
            source: V4BackupSourceV1(
                appBuild: "C31-test",
                appVersion: "C31-test",
                persistentSchemaVersion: 30,
                recordsSchemaVersion: 30,
                workspaceID: fixture.workspace.rawValue
            )
        )

        func packageRecords(
            measurementIntegrity: [V18BackupMeasurementIntegrityRecordV1],
            authorityCriterion: [V11BackupAuthorityCriterionRecordV1]
        ) -> V4BackupRecordsV1 {
            V4BackupRecordsV1(
                authorityCriterion: authorityCriterion,
                assets: [],
                evidenceFiles: [],
                issues: [],
                packets: [],
                recordsSchemaVersion: 30,
                reports: [],
                sites: [],
                workflowRecords: [],
                measurementIntegrity: measurementIntegrity,
                lighting: lightingRows
            )
        }
        func validateLightingPackage(
            measurementIntegrity: [V18BackupMeasurementIntegrityRecordV1],
            authorityCriterion: [V11BackupAuthorityCriterionRecordV1],
            captures: [MeasurementCaptureV1],
            bindings: [LightingMeasurementCaptureBindingV1],
            quality: [MeasurementQualityAssessmentV1]
        ) throws {
            try LightingClaimAdmissionV1.validateMeasured(
                measuredClaim,
                observation: observation,
                plan: plan,
                captures: captures,
                bindings: bindings,
                protocolRelease: fixture.protocolRelease,
                instrument: fixture.instrument,
                calibration: fixture.currentCalibration,
                quality: quality
            )
            let records = packageRecords(
                measurementIntegrity: measurementIntegrity,
                authorityCriterion: authorityCriterion
            )
            try V31LightingImportBoundaryV1.validate(
                persistent: 31,
                records: 30,
                rows: lightingRows
            )
            try C31LightingPackageValidationV1.validate(records)
            try C31LightingBackupRestorePolicyV1.validate(
                lightingRows,
                mode: .replaceExisting
            )
            try BackupPackageValidatorV1().validateMeasurementIntegrity(
                records,
                manifest: measurementManifest
            )
        }
        try validateLightingPackage(
            measurementIntegrity: completeMeasurementRows,
            authorityCriterion: [protocolRow],
            captures: [fixture.capture],
            bindings: [captureBinding],
            quality: [fixture.qualityClear]
        )

        let missingCaptureRows = completeMeasurementRows.filter {
            !($0.kind == .measurementCapture && $0.id == fixture.capture.captureID)
        }
        XCTAssertThrowsError(
            try validateLightingPackage(
                measurementIntegrity: missingCaptureRows,
                authorityCriterion: [protocolRow],
                captures: [],
                bindings: [],
                quality: []
            )
        )
        let mismatchedCaptureRows = try completeMeasurementRows.map { row in
            guard row.kind == .measurementCapture,
                  row.id == fixture.capture.captureID else { return row }
            return measurementRecord(
                row.kind,
                id: row.id,
                revision: row.revision,
                canonicalData: try MeasurementIntegrityCanonicalCodecV1.encode(fixture.secondCapture)
            )
        }
        XCTAssertThrowsError(
            try validateLightingPackage(
                measurementIntegrity: mismatchedCaptureRows,
                authorityCriterion: [protocolRow],
                captures: [fixture.capture],
                bindings: [captureBinding],
                quality: [fixture.qualityClear]
            )
        )

        let missingInstrumentRows = completeMeasurementRows.filter {
            $0.kind != .instrumentReference
        }
        XCTAssertThrowsError(
            try validateLightingPackage(
                measurementIntegrity: missingInstrumentRows,
                authorityCriterion: [protocolRow],
                captures: [fixture.capture],
                bindings: [captureBinding],
                quality: [fixture.qualityClear]
            )
        )
        let mismatchedInstrumentRows = completeMeasurementRows.map { row in
            guard row.kind == .instrumentReference else { return row }
            return V18BackupMeasurementIntegrityRecordV1(
                kind: row.kind,
                id: row.id,
                workspaceID: C31LightingTestSupport.id(901),
                revision: row.revision,
                canonicalData: row.canonicalData
            )
        }
        XCTAssertThrowsError(
            try validateLightingPackage(
                measurementIntegrity: mismatchedInstrumentRows,
                authorityCriterion: [protocolRow],
                captures: [fixture.capture],
                bindings: [captureBinding],
                quality: [fixture.qualityClear]
            )
        )

        let missingCalibrationRows = completeMeasurementRows.filter {
            $0.kind != .calibrationSnapshot
        }
        XCTAssertThrowsError(
            try validateLightingPackage(
                measurementIntegrity: missingCalibrationRows,
                authorityCriterion: [protocolRow],
                captures: [fixture.capture],
                bindings: [captureBinding],
                quality: [fixture.qualityClear]
            )
        )
        let mismatchedCalibrationRows = completeMeasurementRows.map { row in
            guard row.kind == .calibrationSnapshot else { return row }
            return V18BackupMeasurementIntegrityRecordV1(
                kind: row.kind,
                id: row.id,
                workspaceID: row.workspaceID,
                revision: row.revision,
                canonicalData: (try? MeasurementIntegrityCanonicalCodecV1.encode(fixture.expiredCalibration)) ?? row.canonicalData
            )
        }
        XCTAssertThrowsError(
            try validateLightingPackage(
                measurementIntegrity: mismatchedCalibrationRows,
                authorityCriterion: [protocolRow],
                captures: [fixture.capture],
                bindings: [captureBinding],
                quality: [fixture.qualityClear]
            )
        )

        let missingQualityRows = completeMeasurementRows.filter {
            $0.kind != .qualityAssessment
        }
        XCTAssertThrowsError(
            try validateLightingPackage(
                measurementIntegrity: missingQualityRows,
                authorityCriterion: [protocolRow],
                captures: [fixture.capture],
                bindings: [captureBinding],
                quality: []
            )
        )
        let mismatchedQualityRows = completeMeasurementRows.map { row in
            guard row.kind == .qualityAssessment else { return row }
            return V18BackupMeasurementIntegrityRecordV1(
                kind: row.kind,
                id: row.id,
                workspaceID: row.workspaceID,
                revision: row.revision,
                canonicalData: (try? MeasurementIntegrityCanonicalCodecV1.encode(fixture.qualityReview)) ?? row.canonicalData
            )
        }
        XCTAssertThrowsError(
            try validateLightingPackage(
                measurementIntegrity: mismatchedQualityRows,
                authorityCriterion: [protocolRow],
                captures: [fixture.capture],
                bindings: [captureBinding],
                quality: [fixture.qualityClear]
            )
        )

        XCTAssertThrowsError(
            try validateLightingPackage(
                measurementIntegrity: completeMeasurementRows,
                authorityCriterion: [],
                captures: [fixture.capture],
                bindings: [captureBinding],
                quality: [fixture.qualityClear]
            )
        )
        let mismatchedC40ProvenanceRows = [
            V11BackupAuthorityCriterionRecordV1(
                kind: protocolRow.kind,
                id: protocolRow.id,
                workspaceID: protocolRow.workspaceID,
                canonicalData: Data("forged-c40-provenance".utf8)
            )
        ]
        XCTAssertThrowsError(
            try validateLightingPackage(
                measurementIntegrity: completeMeasurementRows,
                authorityCriterion: mismatchedC40ProvenanceRows,
                captures: [fixture.capture],
                bindings: [captureBinding],
                quality: [fixture.qualityClear]
            )
        )

        let duplicateSemanticKeyRows = (lightingRows + [lightingRows[0]]).sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
        for _ in 0..<2 {
            XCTAssertThrowsError(try LightingBackupRecordSetV1.decode(duplicateSemanticKeyRows))
            XCTAssertThrowsError(
                try V31LightingImportBoundaryV1.validate(
                    persistent: 31,
                    records: 30,
                    rows: duplicateSemanticKeyRows
                )
            )
            XCTAssertThrowsError(
                try C31LightingBackupRestorePolicyV1.validate(
                    duplicateSemanticKeyRows,
                    mode: .replaceExisting
                )
            )
        }

        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyLighting))
        XCTAssertTrue(corpus.lifecycleDimensions.contains("BACKUP_RESTORE_REPLAY"))
        XCTAssertTrue(corpus.lifecycleDimensions.contains("SEARCH_REBUILD"))
        XCTAssertTrue(corpus.lifecycleDimensions.contains("DELETE_ERASE"))
        XCTAssertTrue(corpus.exclusions.contains("NO_PROVIDER_OR_ACCOUNT_FOOTPRINT"))
        XCTAssertTrue(corpus.exclusions.contains("NO_AUTOMATIC_COMPLIANCE_OR_SAFETY_CLAIM"))
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingPersistenceEnrollmentV1.recordsSchemaVersion, 30)
        XCTAssertEqual(LightingPersistenceEnrollmentV1.totalModelCount, 109)
    }
}

@MainActor
private final class C31InterruptedLightingWriter: LightingCanonicalWorkspaceWritingV1 {
    private(set) var attempts = 0
    private(set) var recordedOperationDigests: [String] = []

    func commitLighting(_ operation: LightingWriteOperationV1) throws -> MutationReceiptV1 {
        attempts += 1
        recordedOperationDigests.append(try LightingCanonicalCodecV1.sha256(operation))
        throw C31LightingTestError.interrupted
    }
}

import Foundation
import XCTest

@testable import FieldEvidenceApp

private final class C45AssetSemanticLifecycleCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityDelegatesLocatorIdentityToC27() {
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.createsSecondLocatorStore)
        XCTAssertEqual(ManualShortCodeV1.externalKeyNamespace, "assetrounds.asset-label.short-code.v1")
        XCTAssertEqual(Set(AssetLocatorStateV1.allCases), [.active, .retired, .revoked, .replaced])
    }
}

private final class C51V924AssetSemanticLifecycleAnchorTests: XCTestCase {
    func testV23P03C51AssetSemanticsCarryNoScheduleOrOccurrenceTruth() {
        XCTAssertFalse(C51AssetScheduleBoundaryV1.assetRowsCarryScheduleClosure)
        XCTAssertFalse(C51AssetScheduleBoundaryV1.assetIdentityIsOccurrenceIdentity)
        XCTAssertTrue(C51AssetScheduleBoundaryV1.canonicalAssetWriterRemainsUnchanged)
        XCTAssertTrue(C51AssetSemanticsScheduleLifecycleBoundaryV1.closureMetadataIsDerivedOnly)
    }
}

private final class C30EvidenceContextAnchorV9_24AssetSemanticLifecycle: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

@MainActor
final class V9_24AssetSemanticLifecycleTests: XCTestCase {
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
    private let digest = String(repeating: "a", count: 64)

    func testV23P03C39ExactEnumsAndImmutableLifecycleHistory() throws {
        XCTAssertEqual(
            Set(AssetSemanticCompatibilityPolicyV1.allCases),
            [.exactReleaseOnly, .sameSemanticIDSuccessor]
        )
        XCTAssertEqual(
            Set(AssetWorkflowCapabilityBindingDispositionV1.allCases),
            [.bound, .ended]
        )
        XCTAssertEqual(
            Set(AssetProductIdentifierKindV1.allCases),
            [.manufacturer, .model, .serial, .lot, .part, .upcGtin, .externalCode]
        )
        XCTAssertEqual(
            Set(AssetProductIdentifierProvenanceV1.allCases),
            [.humanRecorded, .importedExternalEvidence]
        )
        XCTAssertEqual(
            Set(AssetProductIdentifierReviewStateV1.allCases),
            [.unreviewed, .reviewedAsRecorded, .duplicateRecorded, .unknownRecorded]
        )
        XCTAssertEqual(
            Set(AssetLifecycleEventKindV1.allCases),
            [
                .commissioningNotRecorded, .activeRecorded, .retiredRecorded,
                .replacedRecorded, .classificationChangedRecorded
            ]
        )
        XCTAssertEqual(
            Set(WorkSubjectKindV1.allCases),
            [.site, .locationNode, .asset, .compositionComponent, .functionalRelationship]
        )

        let workspaceID = workspace("00000000-0000-0000-0000-000000000101")
        let assetID = uuid("00000000-0000-0000-0000-000000000201")
        let mutationID = try mutation("00000000-0000-0000-0000-000000000301")
        let catalog = try makeCatalog(workspaceID: workspaceID, assetID: assetID)
        let binding = try makeKindBinding(
            workspaceID: workspaceID,
            assetID: assetID,
            mutationID: mutationID,
            catalog: catalog
        )
        try binding.validate(against: catalog)

        let commissioning = AssetLifecycleEventV1.commissioningNotRecorded(
            try makeLifecycleRecord(
                kind: AssetLifecycleEventKindV1.commissioningNotRecorded,
                workspaceID: workspaceID,
                assetID: assetID,
                mutationID: mutationID,
                eventID: "00000000-0000-0000-0000-000000000401"
            )
        )
        let active = AssetLifecycleEventV1.activeRecorded(
            try makeLifecycleRecord(
                kind: AssetLifecycleEventKindV1.activeRecorded,
                workspaceID: workspaceID,
                assetID: assetID,
                mutationID: mutationID,
                eventID: "00000000-0000-0000-0000-000000000402"
            )
        )
        let retired = AssetLifecycleEventV1.retiredRecorded(
            try makeLifecycleRecord(
                kind: AssetLifecycleEventKindV1.retiredRecorded,
                workspaceID: workspaceID,
                assetID: assetID,
                mutationID: mutationID,
                eventID: "00000000-0000-0000-0000-000000000403"
            )
        )
        let classification = AssetLifecycleEventV1.classificationChangedRecorded(
            try makeLifecycleRecord(
                kind: AssetLifecycleEventKindV1.classificationChangedRecorded,
                workspaceID: workspaceID,
                assetID: assetID,
                mutationID: mutationID,
                eventID: "00000000-0000-0000-0000-000000000404",
                kindBindingEventID: binding.eventID
            )
        )
        let successor = try makeSuccessor(
            workspaceID: workspaceID,
            predecessorAssetID: assetID,
            mutationID: mutationID
        )
        let replacement = AssetLifecycleEventV1.replacedRecorded(
            try makeLifecycleRecord(
                kind: AssetLifecycleEventKindV1.replacedRecorded,
                workspaceID: workspaceID,
                assetID: assetID,
                mutationID: mutationID,
                eventID: "00000000-0000-0000-0000-000000000405",
                successorLinkID: successor.linkID
            )
        )

        let history = [commissioning, active, retired, replacement, classification]
        XCTAssertEqual(history.map(\.kind), AssetLifecycleEventKindV1.allCases)
        try history.forEach { try $0.validate() }
        try classification.validateAtomicReference(kindBinding: binding)
        try replacement.validateAtomicReference(successorLink: successor)
        try AssetSuccessorLinkV1.validateAcyclic([successor])

        XCTAssertEqual(active.record.revision, 1)
        XCTAssertEqual(retired.record.predecessorEventID, nil)
        XCTAssertEqual(classification.record.kindBindingEventID, binding.eventID)
        XCTAssertEqual(replacement.record.successorLinkID, successor.linkID)
    }

    func testV23P03C39CatalogProductAndScopedSnapshotRoundTrip() throws {
        let workspaceID = workspace("00000000-0000-0000-0000-000000000111")
        let assetID = uuid("00000000-0000-0000-0000-000000000211")
        let mutationID = try mutation("00000000-0000-0000-0000-000000000311")
        let catalog = try makeCatalog(workspaceID: workspaceID, assetID: assetID)
        let binding = try makeKindBinding(
            workspaceID: workspaceID,
            assetID: assetID,
            mutationID: mutationID,
            catalog: catalog
        )
        let capability = try AssetSemanticCapabilityIDV1("capability.inspect")
        let workflow = try AssetWorkflowCapabilityBindingEventV1(
            eventID: uuid("00000000-0000-0000-0000-000000000411"),
            workspaceID: workspaceID,
            assetID: assetID,
            kindBindingEventID: binding.eventID,
            kindBindingRevision: binding.revision,
            workflowPackageRelease: catalog.packageRelease,
            capabilityIDs: [capability],
            disposition: .bound,
            predecessorEventID: nil,
            revision: 1,
            mutationID: mutationID,
            recordedAt: fixedDate,
        )
        try workflow.validate()

        let identifier = AssetProductIdentifierV1(
            kind: .serial,
            value: "SN-001",
            normalizedComparisonValue: "sn-001",
            issuer: "local-record",
            provenance: .humanRecorded,
            reviewState: .reviewedAsRecorded,
            effectiveFrom: fixedDate,
            effectiveUntil: fixedDate.addingTimeInterval(60)
        )
        try identifier.validate()
        let identity = try AssetProductIdentityV1(
            identityID: uuid("00000000-0000-0000-0000-000000000511"),
            workspaceID: workspaceID,
            assetID: assetID,
            identifiers: [identifier],
            predecessorIdentityID: nil,
            revision: 1,
            mutationID: mutationID,
            recordedAt: fixedDate,
        )
        let subject = WorkSubjectReferenceV1(
            kind: .asset,
            subjectID: assetID,
            revision: 1,
            ownerAssetID: nil
        )
        let semanticBinding = try WorkSubjectSemanticBindingSnapshotV1(
            assetID: assetID,
            kindBindingEventID: binding.eventID,
            kindBindingRevision: binding.revision,
            catalogRelease: catalog.reference,
            semanticID: "asset.kind.example",
            workflowPackageReleases: [catalog.packageRelease]
        )
        let scope = try WorkSubjectScopeSnapshotV1(
            snapshotID: uuid("00000000-0000-0000-0000-000000000611"),
            workspaceID: workspaceID,
            siteID: uuid("00000000-0000-0000-0000-000000000711"),
            subjects: [subject],
            semanticBindings: [semanticBinding],
            workspaceRevision: 1,
            recordedAt: fixedDate,
        )

        try catalog.validate()
        try scope.validate()
        XCTAssertEqual(try roundTrip(catalog), catalog)
        XCTAssertEqual(try roundTrip(binding), binding)
        XCTAssertEqual(try roundTrip(workflow), workflow)
        XCTAssertEqual(try roundTrip(identity), identity)
        XCTAssertEqual(try roundTrip(scope), scope)
        XCTAssertEqual(try catalog.definition(semanticID: "asset.kind.example").capabilityIDs, [capability])
        XCTAssertEqual(identity.identifiers.first?.effectiveUntil, fixedDate.addingTimeInterval(60))
        XCTAssertEqual(scope.semanticBindings.first?.semanticID, "asset.kind.example")
    }

    func testV23P03C39PersistentRowPreservesFractionalDateAndDigest() throws {
        let workspaceID = workspace("00000000-0000-0000-0000-000000000151")
        let assetID = uuid("00000000-0000-0000-0000-000000000251")
        let mutationID = try mutation("00000000-0000-0000-0000-000000000351")
        let catalog = try AssetSemanticCatalogReleaseV1(
            releaseID: uuid("00000000-0000-0000-0000-000000000951"),
            packageRelease: try PackageReleaseIdentityV1(
                packageID: "com.field-evidence.c39.persistence",
                schemaVersion: 1,
                contentVersion: 1
            ),
            revision: 1,
            definitions: [try AssetKindDefinitionV1(
                semanticID: "asset.kind.example",
                displayNameLocalizationKey: "asset.semantic.kind",
                capabilityIDs: [],
                compatibilityPolicy: .exactReleaseOnly
            )],
            releasedAt: fixedDate
        )
        let recordedAt = Date(timeIntervalSince1970: 1_735_689_600.125)
        let canonical = try AssetKindBindingEventV1.canonical(
            eventID: uuid("00000000-0000-0000-0000-000000000451"),
            workspaceID: workspaceID,
            assetID: assetID,
            catalogRelease: catalog.reference,
            semanticID: "asset.kind.example",
            predecessorEventID: nil,
            revision: 1,
            mutationID: mutationID,
            recordedAt: recordedAt
        )
        let draft = AssetKindBindingEventV1(
            eventID: canonical.eventID,
            workspaceID: canonical.workspaceID,
            assetID: canonical.assetID,
            catalogRelease: canonical.catalogRelease,
            semanticID: canonical.semanticID,
            predecessorEventID: canonical.predecessorEventID,
            revision: canonical.revision,
            mutationID: canonical.mutationID,
            recordedAt: canonical.recordedAt,
            eventSHA256: digest
        )

        let row = try AssetKindBindingEventRow(canonical)
        let persisted = try row.value()
        XCTAssertEqual(persisted, canonical)
        XCTAssertEqual(persisted.recordedAt, recordedAt)
        XCTAssertEqual(
            persisted.eventSHA256,
            try persisted.rebound(to: workspaceID).eventSHA256
        )
        XCTAssertEqual(
            try AssetSemanticCanonicalCodecV1.decode(
                AssetKindBindingEventV1.self,
                from: row.canonicalData
            ),
            persisted
        )
        XCTAssertThrowsError(try AssetKindBindingEventRow(draft))
    }

    func testV23P03C39OneAssetAcceptsTwoExplicitCompatiblePackagesOnly() throws {
        let workspaceID = workspace("00000000-0000-0000-0000-000000000141")
        let assetID = uuid("00000000-0000-0000-0000-000000000241")
        let mutationID = try mutation("00000000-0000-0000-0000-000000000341")
        let primary = try PackageReleaseIdentityV1(
            packageID: "com.field-evidence.c39.primary", schemaVersion: 1, contentVersion: 1
        )
        let secondary = try PackageReleaseIdentityV1(
            packageID: "com.field-evidence.c39.secondary", schemaVersion: 1, contentVersion: 1
        )
        let catalog = try AssetSemanticCatalogReleaseV1(
            releaseID: uuid("00000000-0000-0000-0000-000000000941"),
            packageRelease: primary,
            revision: 1,
            definitions: [try AssetKindDefinitionV1(
                semanticID: "asset.kind.shared",
                displayNameLocalizationKey: "asset.semantic.kind",
                capabilityIDs: [],
                compatibleWorkflowPackageReleases: [secondary],
                compatibilityPolicy: .exactReleaseOnly
            )],
            releasedAt: fixedDate
        )
        let kind = try makeKindBinding(
            workspaceID: workspaceID,
            assetID: assetID,
            mutationID: mutationID,
            catalog: catalog,
            semanticID: "asset.kind.shared"
        )
        func workflow(_ id: String, _ package: PackageReleaseIdentityV1)
            throws -> AssetWorkflowCapabilityBindingEventV1 {
            try AssetWorkflowCapabilityBindingEventV1(
                eventID: uuid(id), workspaceID: workspaceID, assetID: assetID,
                kindBindingEventID: kind.eventID, kindBindingRevision: kind.revision,
                workflowPackageRelease: package, capabilityIDs: [], disposition: .bound,
                predecessorEventID: nil, revision: 1, mutationID: mutationID,
                recordedAt: fixedDate
            )
        }
        let primaryBinding = try workflow(
            "00000000-0000-0000-0000-000000001141", primary
        )
        let secondaryBinding = try workflow(
            "00000000-0000-0000-0000-000000001142", secondary
        )
        try AssetSemanticPackageCompatibilityRegistryV1.validateMultiplePackageBindings(
            [primaryBinding, secondaryBinding], kindBinding: kind, catalog: catalog
        )
        let undeclared = try PackageReleaseIdentityV1(
            packageID: "com.field-evidence.c39.undeclared", schemaVersion: 1, contentVersion: 1
        )
        XCTAssertThrowsError(try AssetSemanticPackageCompatibilityRegistryV1.validate(
            kindBinding: kind,
            catalog: catalog,
            workflowBinding: try workflow(
                "00000000-0000-0000-0000-000000001143", undeclared
            )
        ))
    }

    func testV23P03C39HostileUnknownDuplicateCycleAndCrossWorkspaceInputsFailClosed() throws {
        let workspaceID = workspace("00000000-0000-0000-0000-000000000121")
        let foreignWorkspaceID = workspace("00000000-0000-0000-0000-000000000122")
        let assetID = uuid("00000000-0000-0000-0000-000000000221")
        let mutationID = try mutation("00000000-0000-0000-0000-000000000321")
        let capability = try AssetSemanticCapabilityIDV1("capability.inspect")

        XCTAssertThrowsError(
            try AssetSemanticCapabilityIDV1("CAPABILITY.INVALID")
        ) { error in
            XCTAssertEqual(error as? AssetSemanticContractFailureV1, .invalidValue)
        }
        XCTAssertThrowsError(
            try AssetKindDefinitionV1(
                semanticID: "asset.kind.duplicate",
                displayNameLocalizationKey: "asset.semantic.kind",
                capabilityIDs: [capability, capability],
                compatibilityPolicy: .exactReleaseOnly
            )
        ) { error in
            XCTAssertEqual(error as? AssetSemanticContractFailureV1, .invalidValue)
        }

        let catalog = try makeCatalog(workspaceID: workspaceID, assetID: assetID)
        XCTAssertThrowsError(try catalog.definition(semanticID: "asset.kind.missing")) { error in
            XCTAssertEqual(error as? AssetSemanticContractFailureV1, .unknownSemanticID)
        }

        let foreignCatalog = try AssetSemanticCatalogReleaseV1(
            releaseID: uuid("00000000-0000-0000-0000-000000000821"),
            packageRelease: try PackageReleaseIdentityV1(
                packageID: "com.field-evidence.c39.foreign",
                schemaVersion: 1,
                contentVersion: 2
            ),
            revision: 1,
            definitions: [try AssetKindDefinitionV1(
                semanticID: "asset.kind.foreign",
                displayNameLocalizationKey: "asset.semantic.kind",
                capabilityIDs: [capability],
                compatibilityPolicy: .exactReleaseOnly
            )],
            releasedAt: fixedDate
        )
        let incompatibleBinding = try makeKindBinding(
            workspaceID: workspaceID,
            assetID: assetID,
            mutationID: mutationID,
            catalog: foreignCatalog,
            semanticID: "asset.kind.example"
        )
        XCTAssertThrowsError(try incompatibleBinding.validate(against: catalog)) { error in
            XCTAssertEqual(error as? AssetSemanticContractFailureV1, .incompatibleRelease)
        }

        let classification = AssetLifecycleEventV1.classificationChangedRecorded(
            try makeLifecycleRecord(
                kind: AssetLifecycleEventKindV1.classificationChangedRecorded,
                workspaceID: foreignWorkspaceID,
                assetID: assetID,
                mutationID: mutationID,
                eventID: "00000000-0000-0000-0000-000000000921",
                kindBindingEventID: try makeKindBinding(
                    workspaceID: workspaceID,
                    assetID: assetID,
                    mutationID: mutationID,
                    catalog: catalog
                ).eventID
            )
        )
        let validBinding = try makeKindBinding(
            workspaceID: workspaceID,
            assetID: assetID,
            mutationID: mutationID,
            catalog: catalog
        )
        XCTAssertThrowsError(try classification.validateAtomicReference(kindBinding: validBinding)) { error in
            XCTAssertEqual(error as? AssetSemanticContractFailureV1, .invalidAtomicReference)
        }

        let successorA = try AssetSuccessorLinkV1.canonical(
            linkID: uuid("00000000-0000-0000-0000-000000001001"),
            workspaceID: workspaceID,
            predecessorAssetID: assetID,
            successorAssetID: uuid("00000000-0000-0000-0000-000000001002"),
            predecessorLinkID: nil,
            revision: 1,
            mutationID: mutationID,
            recordedAt: fixedDate
        )
        let successorB = try AssetSuccessorLinkV1.canonical(
            linkID: uuid("00000000-0000-0000-0000-000000001003"),
            workspaceID: workspaceID,
            predecessorAssetID: successorA.successorAssetID,
            successorAssetID: assetID,
            predecessorLinkID: successorA.linkID,
            revision: 2,
            mutationID: mutationID,
            recordedAt: fixedDate
        )
        XCTAssertThrowsError(try AssetSuccessorLinkV1.validateAcyclic([successorA, successorB])) { error in
            XCTAssertEqual(error as? AssetSemanticContractFailureV1, .cycleDetected)
        }

        let canonical = try AssetSemanticCanonicalCodecV1.encode(catalog)
        var nonCanonical = canonical
        nonCanonical.append(0x20)
        XCTAssertThrowsError(
            try AssetSemanticCanonicalCodecV1.decode(AssetSemanticCatalogReleaseV1.self, from: nonCanonical)
        ) { error in
            XCTAssertEqual(error as? AssetSemanticContractFailureV1, .nonCanonicalData)
        }
        XCTAssertThrowsError(
            try AssetSemanticCanonicalCodecV1.decode(String.self, from: Data(repeating: 0, count: 8_388_609))
        ) { error in
            XCTAssertEqual(error as? AssetSemanticContractFailureV1, .invalidValue)
        }
    }

    func testV23P03C39RecoveryRebindsWorkspaceWithoutRewritingIdentityHistory() throws {
        let sourceWorkspaceID = workspace("00000000-0000-0000-0000-000000000131")
        let destinationWorkspaceID = workspace("00000000-0000-0000-0000-000000000132")
        let assetID = uuid("00000000-0000-0000-0000-000000000231")
        let mutationID = try mutation("00000000-0000-0000-0000-000000000331")
        let catalog = try makeCatalog(workspaceID: sourceWorkspaceID, assetID: assetID)
        let binding = try makeKindBinding(
            workspaceID: sourceWorkspaceID,
            assetID: assetID,
            mutationID: mutationID,
            catalog: catalog
        )
        let workflow = try AssetWorkflowCapabilityBindingEventV1(
            eventID: uuid("00000000-0000-0000-0000-000000001101"),
            workspaceID: sourceWorkspaceID,
            assetID: assetID,
            kindBindingEventID: binding.eventID,
            kindBindingRevision: binding.revision,
            workflowPackageRelease: catalog.packageRelease,
            capabilityIDs: [try AssetSemanticCapabilityIDV1("capability.inspect")],
            disposition: .ended,
            predecessorEventID: nil,
            revision: 2,
            mutationID: mutationID,
            recordedAt: fixedDate
        )
        let identity = try AssetProductIdentityV1(
            identityID: uuid("00000000-0000-0000-0000-000000001201"),
            workspaceID: sourceWorkspaceID,
            assetID: assetID,
            identifiers: [],
            predecessorIdentityID: nil,
            revision: 1,
            mutationID: mutationID,
            recordedAt: fixedDate
        )
        let lifecycle = AssetLifecycleEventV1.retiredRecorded(
            try makeLifecycleRecord(
                workspaceID: sourceWorkspaceID,
                assetID: assetID,
                mutationID: mutationID,
                eventID: "00000000-0000-0000-0000-000000001301"
            )
        )
        let successor = try makeSuccessor(
            workspaceID: sourceWorkspaceID,
            predecessorAssetID: assetID,
            mutationID: mutationID
        )
        let subject = WorkSubjectReferenceV1(kind: .asset, subjectID: assetID, revision: 1, ownerAssetID: nil)
        let scope = try WorkSubjectScopeSnapshotV1(
            snapshotID: uuid("00000000-0000-0000-0000-000000001401"),
            workspaceID: sourceWorkspaceID,
            siteID: uuid("00000000-0000-0000-0000-000000001501"),
            subjects: [subject],
            semanticBindings: [],
            workspaceRevision: 1,
            recordedAt: fixedDate
        )

        let reboundBinding = try binding.rebound(to: destinationWorkspaceID)
        let reboundWorkflow = try workflow.rebound(to: destinationWorkspaceID)
        let reboundIdentity = try identity.rebound(to: destinationWorkspaceID)
        let reboundLifecycle = try lifecycle.rebound(to: destinationWorkspaceID)
        let reboundSuccessor = try successor.rebound(to: destinationWorkspaceID)
        let reboundScope = try scope.rebound(to: destinationWorkspaceID)

        XCTAssertEqual(reboundBinding.eventID, binding.eventID)
        XCTAssertEqual(reboundBinding.assetID, binding.assetID)
        XCTAssertEqual(reboundBinding.workspaceID, destinationWorkspaceID)
        XCTAssertNotEqual(reboundBinding.eventSHA256, binding.eventSHA256)
        XCTAssertEqual(reboundWorkflow.eventID, workflow.eventID)
        XCTAssertEqual(reboundWorkflow.workspaceID, destinationWorkspaceID)
        XCTAssertEqual(reboundIdentity.identityID, identity.identityID)
        XCTAssertEqual(reboundIdentity.workspaceID, destinationWorkspaceID)
        XCTAssertEqual(reboundLifecycle.record.eventID, lifecycle.record.eventID)
        XCTAssertEqual(reboundLifecycle.record.workspaceID, destinationWorkspaceID)
        XCTAssertEqual(reboundSuccessor.linkID, successor.linkID)
        XCTAssertEqual(reboundSuccessor.workspaceID, destinationWorkspaceID)
        XCTAssertEqual(reboundScope.snapshotID, scope.snapshotID)
        XCTAssertEqual(reboundScope.workspaceID, destinationWorkspaceID)
        XCTAssertEqual(reboundScope.subjects, scope.subjects)
        XCTAssertEqual(reboundScope.semanticBindings, scope.semanticBindings)
        try reboundBinding.validate(against: catalog)
        try reboundWorkflow.validate()
        try reboundIdentity.validate()
        try reboundLifecycle.validate()
        try reboundSuccessor.validate()
        try reboundScope.validate()
    }

    private var fixedDate: Date { Date(timeIntervalSince1970: 1_735_689_600) }

    private func uuid(_ value: String) -> UUID { UUID(uuidString: value)! }

    private func workspace(_ value: String) -> WorkspaceID {
        WorkspaceID(rawValue: uuid(value))
    }

    private func mutation(_ value: String) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: uuid(value))
    }

    private func makeCatalog(workspaceID: WorkspaceID, assetID: UUID) throws -> AssetSemanticCatalogReleaseV1 {
        _ = workspaceID
        _ = assetID
        return try AssetSemanticCatalogReleaseV1(
            releaseID: uuid("00000000-0000-0000-0000-000000000901"),
            packageRelease: try PackageReleaseIdentityV1(
                packageID: "com.field-evidence.c39",
                schemaVersion: 1,
                contentVersion: 1
            ),
            revision: 1,
            definitions: [try AssetKindDefinitionV1(
                semanticID: "asset.kind.example",
                displayNameLocalizationKey: "asset.semantic.kind",
                descriptionLocalizationKey: "asset.semantic.heading",
                capabilityIDs: [try AssetSemanticCapabilityIDV1("capability.inspect")],
                compatibilityPolicy: .sameSemanticIDSuccessor
            )],
            releasedAt: fixedDate
        )
    }

    private func makeKindBinding(
        workspaceID: WorkspaceID,
        assetID: UUID,
        mutationID: MutationIDV1,
        catalog: AssetSemanticCatalogReleaseV1,
        semanticID: String = "asset.kind.example"
    ) throws -> AssetKindBindingEventV1 {
        try AssetKindBindingEventV1.canonical(
            eventID: uuid("00000000-0000-0000-0000-000000000902"),
            workspaceID: workspaceID,
            assetID: assetID,
            catalogRelease: catalog.reference,
            semanticID: semanticID,
            predecessorEventID: nil,
            revision: 1,
            mutationID: mutationID,
            recordedAt: fixedDate
        )
    }

    private func makeLifecycleRecord(
        kind: AssetLifecycleEventKindV1 = .retiredRecorded,
        workspaceID: WorkspaceID,
        assetID: UUID,
        mutationID: MutationIDV1,
        eventID: String,
        kindBindingEventID: UUID? = nil,
        successorLinkID: UUID? = nil
    ) throws -> AssetLifecycleEventRecordV1 {
        try AssetLifecycleEventRecordV1.canonical(
            for: kind,
            eventID: uuid(eventID),
            workspaceID: workspaceID,
            assetID: assetID,
            predecessorEventID: nil,
            revision: 1,
            mutationID: mutationID,
            recordedAt: fixedDate,
            kindBindingEventID: kindBindingEventID,
            successorLinkID: successorLinkID
        )
    }

    private func makeSuccessor(
        workspaceID: WorkspaceID,
        predecessorAssetID: UUID,
        mutationID: MutationIDV1
    ) throws -> AssetSuccessorLinkV1 {
        try AssetSuccessorLinkV1.canonical(
            linkID: uuid("00000000-0000-0000-0000-000000000903"),
            workspaceID: workspaceID,
            predecessorAssetID: predecessorAssetID,
            successorAssetID: uuid("00000000-0000-0000-0000-000000000904"),
            predecessorLinkID: nil,
            revision: 1,
            mutationID: mutationID,
            recordedAt: fixedDate
        )
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try AssetSemanticCanonicalCodecV1.decode(
            T.self,
            from: AssetSemanticCanonicalCodecV1.encode(value)
        )
    }
}

private final class C27V924TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(AssetLocatorStateV1.allCases.count, 4)
        XCTAssertEqual(AssetLocatorLimitsV1.maximumCandidates, 32)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionStartsWork)
    }
}

extension V9_24AssetSemanticLifecycleTests {
    func testV23P03C41AssetSemanticEndpointsBindRequiredCapabilities() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_240)
        try fixture.sourceCatalog.validate()
        try fixture.targetCatalog.validate()
        try fixture.descriptor.validate(
            sourceCatalog: fixture.sourceCatalog, targetCatalog: fixture.targetCatalog
        )

        let source = try fixture.sourceCatalog.definition(semanticID: "asset.controller")
        let target = try fixture.targetCatalog.definition(semanticID: "asset.zone")
        XCTAssertTrue(source.capabilityIDs.contains(try AssetSemanticCapabilityIDV1("capability.control")))
        XCTAssertTrue(target.capabilityIDs.contains(try AssetSemanticCapabilityIDV1("capability.inspect")))
        XCTAssertEqual(fixture.descriptor.sourceSemanticIDs, ["asset.controller"])
        XCTAssertEqual(fixture.descriptor.targetSemanticIDs, ["asset.zone"])
        XCTAssertEqual(fixture.added.descriptor.semanticID, fixture.descriptor.semanticID)
    }
}

extension V9_24AssetSemanticLifecycleTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorV924AssetSemanticLifecycleTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private final class C33TemporalEvidenceAnchorV924AssetSemanticLifecycle: XCTestCase {
    func testC33V924AssetSemanticLifecycleCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "asset.temporal-evidence-target",
            kind: .video,
            reportProjection: .typedLinkWithDerivativePreview
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "asset.temporal-evidence-target",
            kind: .video,
            reportProjection: .typedLinkWithDerivativePreview
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV924AssetSemanticLifecycle: XCTestCase {
    func testC32V924AssetSemanticLifecycleCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .asset,
            fieldID: "asset-semantics.no-auto-merge",
            value: .singleOption("UNVERIFIED")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .asset,
            fieldID: "asset-semantics.no-auto-merge",
            valueKind: .singleOption
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46V924AssetCompatibilityTests: XCTestCase {
    func testC46AssetLifecycleDoesNotOwnPartyContact() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "asset-lifecycle",
            kind: .email,
            handoff: .email,
            slot: 46024
        )
    }
}

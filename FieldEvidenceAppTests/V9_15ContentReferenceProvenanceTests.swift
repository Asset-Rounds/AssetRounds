import Foundation
import XCTest
@testable import FieldEvidenceApp

private final class C45ContentProvenanceCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityQRPersistsOnlyOpaqueLocatorConvenience() {
        XCTAssertEqual(AssetLabelOpaqueQRPayloadV1.prefix, "AR1")
        XCTAssertEqual(ManualShortCodeV1.externalKeyNamespace, "assetrounds.asset-label.short-code.v1")
        XCTAssertLessThan(ManualShortCodeV1.randomBodyLength, AssetLabelOpaqueQRPayloadV1.maximumPayloadBytes)
    }
}

private final class C30EvidenceContextAnchorV9_15ContentReferenceProvenance: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class V9_15ContentReferenceProvenanceTests: XCTestCase {
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
    private let instant = "2026-08-27T00:00:00Z"

    func testV9_15G01LocatorReplacementPreservesCanonicalContentIdentity() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture["schema"] as? String, "V21P03C05ContentReferenceProvenanceCorpusV1")
        XCTAssertEqual(fixture["failureDisposition"] as? String, "FAIL_CLOSED")
        XCTAssertEqual((fixture["negativeCases"] as? [String])?.count, 18)

        let reference = try makeReference(workspaceID: "workspace.a", contentID: "content.original")
        let observed = try makeObserved(reference)
        var store = try LocalContentStoreV1(workspaceID: reference.workspaceID)
        let initial = try makeLocator(reference, locatorID: "locator.initial", revision: 0)
        try store.store(
            reference: reference,
            locator: initial,
            observed: observed,
            availability: .available(remainingByteCapacity: 4_096)
        )

        let replacement = try makeLocator(reference, locatorID: "locator.replacement", revision: 1)
        try store.replaceLocator(
            contentID: reference.contentID,
            expectedLocatorRevision: 0,
            replacement: replacement
        )
        XCTAssertEqual(try store.resolve(replacement), reference)
        XCTAssertThrowsError(try store.resolve(initial)) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .staleReference)
        }

        let manifest = try ContentManifestV1(
            manifestID: "manifest.g01",
            workspaceID: reference.workspaceID,
            manifestRevision: 1,
            entries: [try manifestEntry(reference, locatorRevision: 1)]
        )
        try ContentIntegrityV1.verify(
            manifest: manifest,
            references: [reference],
            locators: [replacement],
            observed: [observed]
        )
        let bytes = try ContentManifestCanonicalCodecV1.encode(manifest)
        XCTAssertEqual(try ContentManifestCanonicalCodecV1.decode(bytes), manifest)

        let optional = try makeReference(
            workspaceID: reference.workspaceID,
            contentID: "content.optional",
            digestCharacter: "b"
        )
        let optionalLocator = try makeLocator(optional, locatorID: "locator.optional", revision: 0)
        let openabilityManifest = try ContentManifestV1(
            manifestID: "manifest.openability",
            workspaceID: reference.workspaceID,
            manifestRevision: 0,
            entries: [
                try manifestEntry(optional, locatorRevision: 0, requiredForOpen: false),
                try manifestEntry(reference, locatorRevision: 1),
            ]
        )
        try openabilityManifest.validateOpenability(references: [reference], locators: [replacement])
        try openabilityManifest.validate(
            references: [reference, optional],
            locators: [replacement, optionalLocator]
        )
        let collidingOptionalLocator = try makeLocator(
            optional,
            locatorID: replacement.locatorID,
            revision: 0
        )
        XCTAssertThrowsError(try openabilityManifest.validate(
            references: [reference, optional],
            locators: [replacement, collidingOptionalLocator]
        )) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .duplicateIdentity)
        }

        let receipt = try ContentIntegrityReceiptV1(
            receiptID: "receipt.g01",
            reference: reference,
            locator: replacement,
            observed: observed,
            verifiedDigest: XCTUnwrap(reference.digests.digest(for: .sha256))
        )
        XCTAssertEqual(receipt.contentID, reference.contentID)
        let receiptBytes = try JSONEncoder().encode(receipt)
        let decodedReceipt = try JSONDecoder().decode(ContentIntegrityReceiptV1.self, from: receiptBytes)
        try decodedReceipt.validate(reference: reference, locator: replacement, observed: observed)

        var collisionStore = try LocalContentStoreV1(workspaceID: reference.workspaceID)
        try collisionStore.store(
            reference: reference,
            locator: initial,
            observed: observed,
            availability: .available(remainingByteCapacity: 4_096)
        )
        XCTAssertThrowsError(try collisionStore.store(
            reference: optional,
            locator: makeLocator(optional, locatorID: initial.locatorID, revision: 0),
            observed: makeObserved(optional, digestCharacter: "b"),
            availability: .available(remainingByteCapacity: 4_096)
        )) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .duplicateIdentity)
        }
    }

    func testV9_15A01MatchingDigestNeverAliasesAcrossWorkspacesAndUnknownAlgorithmsFailClosed() throws {
        let first = try makeReference(workspaceID: "workspace.a", contentID: "content.same")
        let second = try makeReference(workspaceID: "workspace.b", contentID: "content.same")
        XCTAssertEqual(first.digests, second.digests)
        XCTAssertNotEqual(first.workspaceID, second.workspaceID)
        XCTAssertNotEqual(first.id, second.id)

        var firstStore = try LocalContentStoreV1(workspaceID: first.workspaceID)
        let firstLocator = try makeLocator(first, locatorID: "locator.a", revision: 0)
        try firstStore.store(
            reference: first,
            locator: firstLocator,
            observed: try makeObserved(first),
            availability: .available(remainingByteCapacity: 4_096)
        )
        let foreignLocator = try makeLocator(second, locatorID: "locator.b", revision: 0)
        XCTAssertThrowsError(try firstStore.resolve(foreignLocator)) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .wrongWorkspace)
        }

        let unknown = Data(#"{"algorithm":"MD5","hexadecimalValue":"00000000000000000000000000000000"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ContentDigestV1.self, from: unknown)) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .unknownAlgorithm)
        }
        XCTAssertThrowsError(try ContentDigestSetV1([digest("a"), digest("a")]))
        let duplicateAlgorithm = Data(#"{"values":[{"algorithm":"SHA256","hexadecimalValue":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},{"algorithm":"SHA256","hexadecimalValue":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ContentDigestSetV1.self, from: duplicateAlgorithm)) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .invalidValue)
        }
    }

    func testV9_15H01AssociationOrphanTamperAndRoleConfusionFailClosed() throws {
        let reference = try makeReference(workspaceID: "workspace.a", contentID: "content.original")
        let target = try EvidenceAssociationTargetV1(
            workspaceID: reference.workspaceID,
            kind: .finding,
            targetID: "finding.001",
            targetRevision: 2
        )
        let event = try association(contentID: reference.contentID, target: target)
        let original = try originalProvenance(reference)
        let foreignTarget = try EvidenceAssociationTargetV1(
            workspaceID: "workspace.b",
            kind: .finding,
            targetID: target.targetID,
            targetRevision: target.targetRevision
        )
        XCTAssertThrowsError(try association(contentID: reference.contentID, target: foreignTarget)) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .wrongWorkspace)
        }
        try ContentEvidenceGraphV1.validate(
            references: [reference],
            originalProvenance: [original],
            derivativeProvenance: [],
            associationEvents: [event],
            validTargets: [target]
        )

        let orphan = try association(contentID: "content.missing", target: target)
        XCTAssertThrowsError(try ContentEvidenceGraphV1.validate(
            references: [reference],
            originalProvenance: [original],
            derivativeProvenance: [],
            associationEvents: [orphan],
            validTargets: [target]
        )) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .orphanEvidence)
        }

        let reassignedReference = try makeReference(
            workspaceID: reference.workspaceID,
            contentID: "content.reassigned",
            digestCharacter: "c"
        )
        let reassignment = try EvidenceAssociationV1(
            associationEventID: "association.reassigned",
            workspaceID: reference.workspaceID,
            evidenceID: event.evidenceID,
            expectedEvidenceRevision: 1,
            resultingEvidenceRevision: 2,
            mutationID: "mutation.reassigned",
            action: .reassigned,
            contentID: reassignedReference.contentID,
            target: target,
            previousContentID: reference.contentID,
            previousTarget: target,
            supersedesAssociationEventID: event.associationEventID,
            actorID: "actor.001",
            reason: "Move the stable evidence identity to its corrected content.",
            effectiveAt: instant
        )
        try ContentEvidenceGraphV1.validate(
            references: [reference, reassignedReference],
            originalProvenance: [original, try originalProvenance(reassignedReference)],
            derivativeProvenance: [],
            associationEvents: [event, reassignment],
            validTargets: [target],
            futureC36Exclusions: [try futureReservation(for: reference)]
        )
        let wrongPreviousTarget = try EvidenceAssociationTargetV1(
            workspaceID: reference.workspaceID,
            kind: .finding,
            targetID: "finding.stale",
            targetRevision: 1
        )
        let staleReassignment = try EvidenceAssociationV1(
            associationEventID: "association.stale",
            workspaceID: reference.workspaceID,
            evidenceID: event.evidenceID,
            expectedEvidenceRevision: 1,
            resultingEvidenceRevision: 2,
            mutationID: "mutation.stale",
            action: .reassigned,
            contentID: reassignedReference.contentID,
            target: target,
            previousContentID: reference.contentID,
            previousTarget: wrongPreviousTarget,
            supersedesAssociationEventID: event.associationEventID,
            actorID: "actor.001",
            reason: "Reject a stale prior association target.",
            effectiveAt: instant
        )
        XCTAssertThrowsError(try EvidenceAssociationLedgerV1.validate([event, staleReassignment])) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .staleReference)
        }

        let wrongLength = try ContentIntegrityV1.observe(
            workspaceID: reference.workspaceID,
            contentID: reference.contentID,
            data: payload("a", count: 1_025),
            mediaType: reference.mediaType,
            algorithms: reference.digests.values.map(\.algorithm)
        )
        XCTAssertThrowsError(try ContentIntegrityV1.verify(
            reference: reference,
            locator: makeLocator(reference, locatorID: "locator.hostile", revision: 0),
            observed: wrongLength
        )) { error in
            XCTAssertEqual(error as? ContentIntegrityFailureV1, .byteLengthMismatch)
        }

        let dishonestDerivativeReference = try makeReference(
            workspaceID: reference.workspaceID,
            contentID: "content.derivative",
            digestCharacter: "b",
            byteRole: .immutableOriginal
        )
        let dishonestDerivative = try derivativeProvenance(
            source: reference,
            derivativeContentID: dishonestDerivativeReference.contentID,
            derivativeDigest: digest("b")
        )
        XCTAssertThrowsError(try ContentProvenanceGraphV1.validate(
            references: [reference, dishonestDerivativeReference],
            originals: [original],
            derivatives: [dishonestDerivative]
        )) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .immutableOriginal)
        }

        let explicitNull = Data(#"{"action":"ASSIGNED","actorID":"actor.001","associationEventID":"association.null","contentID":"content.original","effectiveAt":"2026-08-27T00:00:00Z","evidenceID":"evidence.001","expectedEvidenceRevision":0,"mutationID":"mutation.null","previousContentID":null,"reason":"Attach immutable source evidence.","resultingEvidenceRevision":1,"schemaVersion":1,"target":{"kind":"FINDING","targetID":"finding.001","targetRevision":2,"workspaceID":"workspace.a"},"workspaceID":"workspace.a"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(EvidenceAssociationV1.self, from: explicitNull)) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .invalidValue)
        }

        let mixedTransform = Data(#"{"kind":"THUMBNAIL","sanitized":{"sanitizerID":"sanitizer.metadata","sanitizerVersion":"v1"},"thumbnail":{"pixelHeight":240,"pixelWidth":320,"rendererID":"renderer.thumbnail","rendererVersion":"v1"}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ContentDerivativeTransformV1.self, from: mixedTransform))

        let removal = try EvidenceAssociationV1(
            associationEventID: "association.removed",
            workspaceID: reference.workspaceID,
            evidenceID: event.evidenceID,
            expectedEvidenceRevision: 1,
            resultingEvidenceRevision: 2,
            mutationID: "mutation.removed",
            action: .removed,
            contentID: nil,
            target: nil,
            previousContentID: reference.contentID,
            previousTarget: target,
            supersedesAssociationEventID: event.associationEventID,
            actorID: "actor.001",
            reason: "Remove the active evidence binding.",
            effectiveAt: instant
        )
        XCTAssertThrowsError(try ContentEvidenceGraphV1.validate(
            references: [reference],
            originalProvenance: [original],
            derivativeProvenance: [],
            associationEvents: [event, removal],
            validTargets: [target]
        )) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .orphanEvidence)
        }

        XCTAssertThrowsError(try ContentIntegrityReceiptV1(
            receiptID: "receipt.tampered",
            reference: reference,
            locator: makeLocator(reference, locatorID: "locator.tampered", revision: 0),
            observed: wrongLength,
            verifiedDigest: XCTUnwrap(reference.digests.digest(for: .sha256))
        )) { error in
            XCTAssertEqual(error as? ContentIntegrityFailureV1, .byteLengthMismatch)
        }
    }

    func testV9_15I01InterruptedPublicationAndStoreFailuresExposeZeroOrCompleteState() throws {
        for boundary in [
            ContentContractPublicationBoundaryV1.beforeValidation,
            .afterValidationBeforePublication,
        ] {
            XCTAssertEqual(
                try ContentContractRegistryPublisherV1.publish(recoveringFrom: boundary),
                .zero
            )
        }
        let recovered = try ContentContractRegistryPublisherV1.publish(
            recoveringFrom: .afterPublicationBeforeReceipt
        )
        guard case .complete(let registry, let receipt) = recovered else {
            return XCTFail("publication did not recover complete state")
        }
        XCTAssertEqual(registry.persistentContractSchema, "KERNEL_MEDIA_V1")
        XCTAssertEqual(registry.downgradeDisposition, "DORMANT_REVERT_ALLOWED")
        XCTAssertFalse(receipt.nativeCompileRan)
        XCTAssertFalse(receipt.hostedDispatchRan)
        XCTAssertFalse(receipt.acceptanceCredit)
        XCTAssertFalse(receipt.releaseCredit)
        let canonicalRegistry = try ContentContractRegistryCanonicalCodecV1.encode(registry)
        XCTAssertEqual(receipt.registrySHA256, KernelCanonicalHashV1.sha256(canonicalRegistry))
        XCTAssertEqual(try ContentContractRegistryCanonicalCodecV1.decode(canonicalRegistry), registry)
        XCTAssertEqual(
            try ContentContractRegistryPublisherV1.recover(
                canonicalData: canonicalRegistry,
                receipt: receipt
            ),
            registry
        )
        XCTAssertNil(try ContentContractRegistryPublisherV1.recover(canonicalData: nil, receipt: nil))

        let openReceipt = Data(#"{"acceptanceCredit":false,"hostedDispatchRan":false,"nativeCompileRan":false,"publicationState":"COMPLETE","registrySHA256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","releaseCredit":false,"requiresAcceptedS10_6Reconciliation":true,"schemaVersion":1,"unexpected":true}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ContentContractRegistryReceiptV1.self, from: openReceipt))
        let forgedReceiptData = Data(#"{"acceptanceCredit":false,"hostedDispatchRan":false,"nativeCompileRan":false,"publicationState":"COMPLETE","registrySHA256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","releaseCredit":false,"requiresAcceptedS10_6Reconciliation":true,"schemaVersion":1}"#.utf8)
        let forgedReceipt = try JSONDecoder().decode(ContentContractRegistryReceiptV1.self, from: forgedReceiptData)
        XCTAssertThrowsError(try ContentContractRegistryPublisherV1.recover(
            canonicalData: canonicalRegistry,
            receipt: forgedReceipt
        )) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .digestMismatch)
        }
        XCTAssertThrowsError(try ContentContractRegistryPublisherV1.recover(
            canonicalData: canonicalRegistry,
            receipt: nil
        )) { error in
            XCTAssertEqual(error as? ContentIntegrityFailureV1, .partialEffect)
        }

        let reference = try makeReference(workspaceID: "workspace.a", contentID: "content.cancelled")
        var store = try LocalContentStoreV1(workspaceID: reference.workspaceID)
        XCTAssertThrowsError(try store.store(
            reference: reference,
            locator: makeLocator(reference, locatorID: "locator.cancelled", revision: 0),
            observed: makeObserved(reference),
            availability: .cancelled
        )) { error in
            XCTAssertEqual(error as? ContentIntegrityFailureV1, .cancelled)
        }
        XCTAssertTrue(store.entries.isEmpty)

        var lowStorageStore = try LocalContentStoreV1(workspaceID: reference.workspaceID)
        XCTAssertThrowsError(try lowStorageStore.store(
            reference: reference,
            locator: makeLocator(reference, locatorID: "locator.low-storage", revision: 0),
            observed: makeObserved(reference),
            availability: .available(remainingByteCapacity: reference.byteLength - 1)
        )) { error in
            XCTAssertEqual(error as? ContentIntegrityFailureV1, .insufficientStorage)
        }
        XCTAssertTrue(lowStorageStore.entries.isEmpty)
    }

    func testV9_15R01DerivativeOnlyRecoveryRetainsImmutableOriginalAndProvenance() throws {
        let original = try makeReference(workspaceID: "workspace.a", contentID: "content.original")
        let derivative = try makeReference(
            workspaceID: original.workspaceID,
            contentID: "content.thumbnail",
            digestCharacter: "b",
            byteRole: .derivative
        )
        let provenance = try derivativeProvenance(
            source: original,
            derivativeContentID: derivative.contentID,
            derivativeDigest: digest("b")
        )
        let originalProvenance = try originalProvenance(original)
        try ContentProvenanceGraphV1.validate(
            references: [original, derivative],
            originals: [originalProvenance],
            derivatives: [provenance]
        )
        let collidingProvenance = try ContentDerivativeProvenanceV1(
            provenanceID: originalProvenance.provenanceID,
            workspaceID: provenance.workspaceID,
            sources: provenance.sources,
            derivativeContentID: provenance.derivativeContentID,
            derivativeDigest: provenance.derivativeDigest,
            transform: provenance.transform,
            metadataSanitizerID: provenance.metadataSanitizerID,
            metadataSanitizerVersion: provenance.metadataSanitizerVersion,
            createdAt: provenance.createdAt
        )
        XCTAssertThrowsError(try ContentProvenanceGraphV1.validate(
            references: [original, derivative],
            originals: [originalProvenance],
            derivatives: [collidingProvenance]
        )) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .duplicateIdentity)
        }

        var store = try LocalContentStoreV1(workspaceID: original.workspaceID)
        let originalLocator = try makeLocator(original, locatorID: "locator.original", revision: 0)
        let derivativeLocator = try makeLocator(derivative, locatorID: "locator.thumbnail", revision: 0)
        try store.store(
            reference: original,
            locator: originalLocator,
            observed: makeObserved(original),
            availability: .available(remainingByteCapacity: 8_192)
        )
        try store.store(
            reference: derivative,
            locator: derivativeLocator,
            observed: makeObserved(derivative, digestCharacter: "b"),
            availability: .available(remainingByteCapacity: 8_192)
        )
        try store.deleteRegenerableDerivative(contentID: derivative.contentID, provenance: provenance)
        XCTAssertNil(store.entries[derivative.contentID])
        XCTAssertEqual(try store.resolve(originalLocator), original)
        XCTAssertEqual(store.immutableOriginals(), [original])
        try store.store(
            reference: derivative,
            locator: derivativeLocator,
            observed: makeObserved(derivative, digestCharacter: "b"),
            availability: .available(remainingByteCapacity: 8_192)
        )
        XCTAssertEqual(try store.resolve(derivativeLocator), derivative)
        XCTAssertThrowsError(try store.deleteRegenerableDerivative(
            contentID: original.contentID,
            provenance: provenance
        )) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .immutableOriginal)
        }

        let reservation = try futureReservation(for: original)
        try ContentEvidenceGraphV1.validate(
            references: [original, derivative],
            originalProvenance: [originalProvenance],
            derivativeProvenance: [provenance],
            associationEvents: [],
            validTargets: [],
            futureC36Exclusions: [reservation]
        )
        let conflictingLifecycleReservation = try FutureC36ContentExclusionV1(
            reservationClass: .prePromotionStagedBytes,
            workspaceID: reservation.workspaceID,
            draftID: reservation.draftID,
            stageID: reservation.stageID,
            commitPlanSHA256: reservation.commitPlanSHA256,
            mutationID: "mutation.staging.conflict",
            contentDigest: reservation.contentDigest
        )
        XCTAssertThrowsError(try ContentEvidenceGraphV1.validate(
            references: [original, derivative],
            originalProvenance: [originalProvenance],
            derivativeProvenance: [provenance],
            associationEvents: [],
            validTargets: [],
            futureC36Exclusions: [reservation, conflictingLifecycleReservation]
        )) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .duplicateIdentity)
        }
        // C36 pre-promotion and CONTENT_PROMOTED_UNBOUND reservations never gain an EvidenceID.
    }

    private func digest(_ character: Character) throws -> ContentDigestV1 {
        try ContentDigestV1(
            algorithm: .sha256,
            hexadecimalValue: KernelCanonicalHashV1.sha256(payload(character))
        )
    }

    private func payload(_ character: Character, count: Int = 1_024) throws -> Data {
        let byte = try XCTUnwrap(String(character).utf8.first)
        return Data(repeating: byte, count: count)
    }

    private func makeReference(
        workspaceID: String,
        contentID: String,
        digestCharacter: Character = "a",
        byteRole: ContentByteRoleV1 = .immutableOriginal
    ) throws -> ContentReferenceV1 {
        try ContentReferenceV1(
            workspaceID: workspaceID,
            contentID: contentID,
            byteLength: 1_024,
            mediaType: "image/jpeg",
            digests: ContentDigestSetV1([digest(digestCharacter)]),
            byteRole: byteRole,
            createdAt: instant
        )
    }

    private func makeLocator(
        _ reference: ContentReferenceV1,
        locatorID: String,
        revision: Int
    ) throws -> ContentLocatorV1 {
        try ContentLocatorV1(
            locatorID: locatorID,
            workspaceID: reference.workspaceID,
            contentID: reference.contentID,
            locatorRevision: revision,
            contentDigest: try XCTUnwrap(reference.digests.digest(for: .sha256)),
            expectedByteLength: reference.byteLength
        )
    }

    private func makeObserved(
        _ reference: ContentReferenceV1,
        digestCharacter: Character = "a"
    ) throws -> ContentObservedBytesV1 {
        try ContentIntegrityV1.observe(
            workspaceID: reference.workspaceID,
            contentID: reference.contentID,
            data: payload(digestCharacter),
            mediaType: reference.mediaType,
            algorithms: reference.digests.values.map(\.algorithm)
        )
    }

    private func manifestEntry(
        _ reference: ContentReferenceV1,
        locatorRevision: Int,
        requiredForOpen: Bool = true
    ) throws -> ContentManifestEntryV1 {
        try ContentManifestEntryV1(
            contentID: reference.contentID,
            expectedByteLength: reference.byteLength,
            mediaType: reference.mediaType,
            digest: XCTUnwrap(reference.digests.digest(for: .sha256)),
            expectedLocatorRevision: locatorRevision,
            requiredForOpen: requiredForOpen
        )
    }

    private func originalProvenance(_ reference: ContentReferenceV1) throws -> ContentOriginalProvenanceV1 {
        try ContentOriginalProvenanceV1(
            provenanceID: "provenance.\(reference.contentID)",
            workspaceID: reference.workspaceID,
            contentID: reference.contentID,
            contentDigest: XCTUnwrap(reference.digests.digest(for: .sha256)),
            origin: .humanCapture,
            recordedAt: instant
        )
    }

    private func derivativeProvenance(
        source: ContentReferenceV1,
        derivativeContentID: String,
        derivativeDigest: ContentDigestV1
    ) throws -> ContentDerivativeProvenanceV1 {
        try ContentDerivativeProvenanceV1(
            provenanceID: "provenance.\(derivativeContentID)",
            workspaceID: source.workspaceID,
            sources: [try ContentSourceBindingV1(
                contentID: source.contentID,
                digest: XCTUnwrap(source.digests.digest(for: .sha256))
            )],
            derivativeContentID: derivativeContentID,
            derivativeDigest: derivativeDigest,
            transform: .thumbnail(try ThumbnailDerivativeV1(
                rendererID: "renderer.thumbnail",
                rendererVersion: "v1",
                pixelWidth: 320,
                pixelHeight: 240
            )),
            metadataSanitizerID: "sanitizer.metadata",
            metadataSanitizerVersion: "v1",
            createdAt: instant
        )
    }

    private func association(
        contentID: String,
        target: EvidenceAssociationTargetV1
    ) throws -> EvidenceAssociationV1 {
        try EvidenceAssociationV1(
            associationEventID: "association.\(contentID)",
            workspaceID: "workspace.a",
            evidenceID: "evidence.001",
            expectedEvidenceRevision: 0,
            resultingEvidenceRevision: 1,
            mutationID: "mutation.\(contentID)",
            action: .assigned,
            contentID: contentID,
            target: target,
            actorID: "actor.001",
            reason: "Attach immutable source evidence.",
            effectiveAt: instant
        )
    }

    private func futureReservation(for reference: ContentReferenceV1) throws -> FutureC36ContentExclusionV1 {
        try FutureC36ContentExclusionV1(
            reservationClass: .contentPromotedUnbound,
            workspaceID: reference.workspaceID,
            draftID: "draft.\(reference.contentID)",
            stageID: "stage.\(reference.contentID)",
            commitPlanSHA256: String(repeating: "d", count: 64),
            mutationID: "mutation.promotion.\(reference.contentID)",
            contentDigest: XCTUnwrap(reference.digests.digest(for: .sha256)),
            contentID: reference.contentID
        )
    }

    private func loadFixture() throws -> [String: Any] {
        let url = Bundle(for: Self.self).url(
            forResource: "V21P03C05ContentReferenceProvenanceCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V21/Content"
        )
        let data = try Data(contentsOf: XCTUnwrap(url))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class C27V915TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(ExternalKeyNormalizationV1.allCases.count, 2)
        XCTAssertEqual(LocatorResolutionOutcomeV1.allCases.count, 8)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.scanMutatesCanonicalState)
    }
}

extension V9_15ContentReferenceProvenanceTests {
    func testC36MediaBoundaryHasNoEvidenceIDBeforeCanonicalCommit() {
        let staged = DraftMediaPromotionBoundaryV1.stagedWithoutEvidenceID(
            stageID: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
            draftID: UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
        )
        let committed = DraftMediaPromotionBoundaryV1.committed(
            contentID: "content.001",
            locatorID: "locator.001"
        )

        XCTAssertFalse(staged.exposesEvidenceID)
        XCTAssertFalse(staged.isCanonical)
        XCTAssertFalse(committed.exposesEvidenceID)
        XCTAssertTrue(committed.isCanonical)
    }
}

extension V9_15ContentReferenceProvenanceTests {
    func testC23FieldReferencePackAnchor() throws {
        XCTAssertEqual(FieldReferenceProvenanceKindV1.allCases, [.licensed, .synthetic])
        XCTAssertEqual(FieldReferenceLicenseScopeV1.allCases.count, 4)
        XCTAssertFalse(FieldReferencePackLifecycleV1.drmOrAccountRequired)
    }
}

extension V9_15ContentReferenceProvenanceTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorV915ContentReferenceProvenanceTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private final class C33TemporalEvidenceAnchorV915ContentReferenceProvenance: XCTestCase {
    func testC33V915ContentReferenceProvenanceCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "content.temporal-immutable-original",
            kind: .video,
            reportProjection: .typedLinkWithDerivativePreview
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "content.temporal-immutable-original",
            kind: .video,
            reportProjection: .typedLinkWithDerivativePreview
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }

    func testC33WaveformTaggedCodableRoundTripsAndRejectsUnknownOrTamperedPayloads() throws {
        let waveform = ContentDerivativeTransformV1.waveform(
            try WaveformDerivativeV1(
                rendererID: "temporal.waveform.renderer",
                rendererVersion: "v1",
                sampleCount: 2_048
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(waveform)
        XCTAssertEqual(
            try JSONDecoder().decode(ContentDerivativeTransformV1.self, from: encoded),
            waveform
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(object["kind"] as? String, "WAVEFORM")
        let payload = try XCTUnwrap(object["waveform"] as? [String: Any])
        XCTAssertEqual(payload["rendererID"] as? String, "temporal.waveform.renderer")
        XCTAssertEqual(payload["rendererVersion"] as? String, "v1")
        XCTAssertEqual(payload["sampleCount"] as? Int, 2_048)

        let unknown = Data(#"{"kind":"SPECTROGRAM","waveform":{"rendererID":"temporal.waveform.renderer","rendererVersion":"v1","sampleCount":2048}}"#.utf8)
        XCTAssertThrowsError(
            try JSONDecoder().decode(ContentDerivativeTransformV1.self, from: unknown)
        ) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .invalidProvenance)
        }

        let mixed = Data(#"{"kind":"WAVEFORM","thumbnail":{"pixelHeight":180,"pixelWidth":320,"rendererID":"temporal.waveform.renderer","rendererVersion":"v1"},"waveform":{"rendererID":"temporal.waveform.renderer","rendererVersion":"v1","sampleCount":2048}}"#.utf8)
        XCTAssertThrowsError(
            try JSONDecoder().decode(ContentDerivativeTransformV1.self, from: mixed)
        )

        let tamperedInner = Data(#"{"kind":"WAVEFORM","waveform":{"rendererID":"temporal.waveform.renderer","rendererVersion":"v1","sampleCount":2048,"untrustedSamples":"embedded"}}"#.utf8)
        XCTAssertThrowsError(
            try JSONDecoder().decode(ContentDerivativeTransformV1.self, from: tamperedInner)
        )

        let invalidPayload = Data(#"{"kind":"WAVEFORM","waveform":{"rendererID":"temporal.waveform.renderer","rendererVersion":"v1","sampleCount":0}}"#.utf8)
        XCTAssertThrowsError(
            try JSONDecoder().decode(ContentDerivativeTransformV1.self, from: invalidPayload)
        ) { error in
            XCTAssertEqual(error as? ContentContractFailureV1, .invalidValue)
        }
    }
}

private final class C32AssistanceAnchorV915ContentReferenceProvenance: XCTestCase {
    func testC32V915ContentReferenceProvenanceCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .evidenceFile,
            fieldID: "content.source-revision",
            value: .text("source-provenance-bound value")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .evidenceFile,
            fieldID: "content.source-revision",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46V915ContentCompatibilityTests: XCTestCase {
    func testC46ContentProvenanceDoesNotBecomeContactSourceBytes() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "content-provenance",
            kind: .email,
            handoff: .email,
            slot: 46015
        )
    }
}

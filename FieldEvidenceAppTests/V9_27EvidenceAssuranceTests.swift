import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_27EvidenceAssuranceTests: XCTestCase {
    func testV23P03C13GoldenVisibilityLinksManifestAndPurposeBoundAttestation() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture()

        try fixture.routineVisibility.validate()
        try fixture.customerPreview.validate()
        try fixture.customerManifest.validateFresh(preview: fixture.customerPreview)
        try fixture.customerAttestation.validate(manifest: fixture.customerManifest)

        XCTAssertEqual(
            try fixture.routineVisibility.decision(for: .customerReport).disposition,
            .included
        )
        XCTAssertEqual(fixture.customerPreview.includedLinks.count, 1)
        XCTAssertEqual(fixture.customerPreview.excludedLinks.count, 1)
        XCTAssertEqual(
            fixture.customerPreview.includedLinks.first?.evidenceID,
            "evidence.customer-safe"
        )
        XCTAssertEqual(
            fixture.customerPreview.excludedLinks.first?.decision.limitation,
            .audienceNotDeclared
        )
        XCTAssertEqual(fixture.customerManifest.sourcePreviewID, fixture.customerPreview.previewID)
        XCTAssertEqual(fixture.customerManifest.snapshotSHA256, fixture.customerPreview.snapshotSHA256)
        XCTAssertEqual(fixture.customerAttestation.purpose, .acknowledgeReport)
        XCTAssertEqual(fixture.customerAttestation.scope.kind, .assuranceManifest)
        XCTAssertEqual(fixture.customerAttestation.manifestID, fixture.customerManifest.manifestID)

        let manifestMutation = try EvidenceAssuranceMutationV1(
            workspaceID: fixture.workspaceID,
            expectedRevision: 0,
            mutationID: fixture.customerManifest.mutationID,
            postImage: .appendManifest(
                manifest: fixture.customerManifest,
                preview: fixture.customerPreview
            )
        )
        let attestationMutation = try EvidenceAssuranceMutationV1(
            workspaceID: fixture.workspaceID,
            expectedRevision: 0,
            mutationID: fixture.customerAttestation.mutationID,
            postImage: .recordAttestation(
                value: fixture.customerAttestation,
                manifest: fixture.customerManifest
            )
        )
        try manifestMutation.validate()
        try attestationMutation.validate()
        XCTAssertEqual(try manifestMutation.affectedIdentity.kind, .assuranceManifest)
        XCTAssertEqual(try attestationMutation.affectedIdentity.kind, .attestation)

        let manifestRow = try AssuranceManifestRow(fixture.customerManifest)
        let attestationRow = try AttestationRow(fixture.customerAttestation)
        XCTAssertEqual(try manifestRow.value(), fixture.customerManifest)
        XCTAssertEqual(try attestationRow.value(), fixture.customerAttestation)

        try assertCanonicalRoundTrip(fixture.customerManifest)
        try assertCanonicalRoundTrip(fixture.customerAttestation)
    }

    func testV23P03C13AlternatePreviewPublicationAndClosedAudienceDisposition() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_100)
        let customerIncludedJSON = try String(
            data: EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerPreview.includedLinks),
            encoding: .utf8
        )

        XCTAssertEqual(fixture.customerPreview.includedLinks.count, 1)
        XCTAssertTrue(fixture.customerPreview.excludedLinks.allSatisfy {
            $0.decision.disposition == .excluded
        })
        XCTAssertTrue(
            fixture.customerPreview.excludedLinks.contains {
                $0.evidenceID == "evidence.internal-canary"
                    && $0.decision.limitation == .audienceNotDeclared
            }
        )
        XCTAssertTrue(
            fixture.customerPreview.excludedLinks.first?.limitationNote?.contains("omitted") == true
        )
        XCTAssertFalse(customerIncludedJSON?.contains("internal-canary") == true)
        XCTAssertFalse(customerIncludedJSON?.contains("restricted-canary") == true)

        let internalPreview = try AssuranceProjectionPreviewV1(
            previewID: C13EvidenceAssuranceTestSupportV1.id(51_180),
            workspaceID: fixture.workspaceID,
            audience: .internalReview,
            snapshotSHA256: fixture.customerPreview.snapshotSHA256,
            projectionVersion: C13EvidenceAssuranceTestSupportV1.projectionVersion,
            links: [fixture.internalLink],
            createdAt: C13EvidenceAssuranceTestSupportV1.fixedDate.addingTimeInterval(4)
        )
        XCTAssertEqual(internalPreview.includedLinks.map(\.evidenceID), ["evidence.internal-review"])
        XCTAssertTrue(internalPreview.excludedLinks.isEmpty)
        try internalPreview.validate()
    }

    private func assertC13AudienceBySensitivityMatrixDeniesUndeclaredEvidence() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_200)
        let matrix: [(EvidenceVisibilityV1, EvidenceAudienceV1, EvidenceInclusionDispositionV1, EvidenceLimitationV1)] = [
            (fixture.routineVisibility, .internalReview, .included, .none),
            (fixture.routineVisibility, .customerReport, .included, .none),
            (fixture.routineVisibility, .externalCollaborator, .included, .none),
            (fixture.internalOnlyVisibility, .internalReview, .included, .none),
            (fixture.internalOnlyVisibility, .customerReport, .excluded, .audienceNotDeclared),
            (fixture.internalOnlyVisibility, .externalCollaborator, .excluded, .audienceNotDeclared),
            (fixture.restrictedVisibility, .internalReview, .included, .none),
            (fixture.restrictedVisibility, .customerReport, .included, .none),
            (fixture.restrictedVisibility, .externalCollaborator, .excluded, .sensitivityRestricted),
            (fixture.highlyRestrictedVisibility, .internalReview, .included, .none),
            (fixture.highlyRestrictedVisibility, .customerReport, .excluded, .sensitivityRestricted),
            (fixture.highlyRestrictedVisibility, .externalCollaborator, .excluded, .sensitivityRestricted),
        ]

        for (visibility, audience, disposition, limitation) in matrix {
            let decision = try visibility.decision(for: audience)
            XCTAssertEqual(decision.audience, audience)
            XCTAssertEqual(decision.disposition, disposition)
            XCTAssertEqual(decision.limitation, limitation)
        }

        let changedSnapshotPreview = try AssuranceProjectionPreviewV1(
            previewID: C13EvidenceAssuranceTestSupportV1.id(51_280),
            workspaceID: fixture.workspaceID,
            audience: .customerReport,
            snapshotSHA256: String(repeating: "b", count: 64),
            projectionVersion: C13EvidenceAssuranceTestSupportV1.projectionVersion,
            links: fixture.customerPreview.includedLinks + fixture.customerPreview.excludedLinks,
            createdAt: C13EvidenceAssuranceTestSupportV1.fixedDate.addingTimeInterval(5)
        )
        XCTAssertThrowsError(
            try fixture.customerManifest.validateFresh(preview: changedSnapshotPreview)
        ) { error in
            XCTAssertEqual(error as? EvidenceAssuranceFailureV1, .stalePreview)
        }
    }

    func testV23P03C13HostileScopePurposeDigestSupersessionVoidAndForbiddenInputsFailClosed() throws {
        try assertC13AudienceBySensitivityMatrixDeniesUndeclaredEvidence()
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_300)

        var alteredPurpose = try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerAttestation)
        let alteredText = try XCTUnwrap(String(data: alteredPurpose, encoding: .utf8))
            .replacingOccurrences(of: "ACKNOWLEDGE_REPORT", with: "CONFIRM_LOCAL_REVIEW")
        alteredPurpose = Data(alteredText.utf8)
        XCTAssertThrowsError(
            try EvidenceAssuranceCanonicalCodecV1.decode(AttestationV1.self, from: alteredPurpose)
        ) { error in
            XCTAssertEqual(error as? EvidenceAssuranceFailureV1, .digestMismatch)
        }

        XCTAssertFalse(
            fixture.customerPreview.includedLinks.contains { $0.evidenceID == "evidence.internal-canary" }
        )
        XCTAssertTrue(
            fixture.customerPreview.excludedLinks.contains { $0.evidenceID == "evidence.internal-canary" }
        )

        XCTAssertThrowsError(
            try AttestationV1(
                attestationID: fixture.customerAttestation.attestationID,
                workspaceID: fixture.workspaceID,
                purpose: fixture.customerAttestation.purpose,
                scope: fixture.customerAttestation.scope,
                manifest: fixture.customerManifest,
                declaredActor: fixture.actor,
                method: fixture.customerAttestation.method,
                action: .voided,
                occurredAt: C13EvidenceAssuranceTestSupportV1.fixedDate.addingTimeInterval(6),
                recordedAt: C13EvidenceAssuranceTestSupportV1.fixedDate.addingTimeInterval(6),
                supersedesAttestationID: fixture.customerAttestation.attestationID,
                revision: 2,
                mutationID: try C13EvidenceAssuranceTestSupportV1.mutation(51_371)
            )
        ) { error in
            XCTAssertEqual(error as? EvidenceAssuranceFailureV1, .digestMismatch)
        }

        let appendMutation = try EvidenceAssuranceMutationV1(
            workspaceID: fixture.workspaceID,
            expectedRevision: 0,
            mutationID: fixture.routineVisibility.mutationID,
            postImage: .appendVisibility(fixture.routineVisibility)
        )
        try appendMutation.validate()

        let successorVisibility = try EvidenceVisibilityV1(
            visibilityID: C13EvidenceAssuranceTestSupportV1.id(51_372),
            workspaceID: fixture.workspaceID,
            sensitivity: .routine,
            allowedAudiences: [.internalReview, .customerReport],
            effectiveAt: C13EvidenceAssuranceTestSupportV1.fixedDate.addingTimeInterval(7),
            supersedesVisibilityID: fixture.routineVisibility.visibilityID,
            revision: 2,
            mutationID: try C13EvidenceAssuranceTestSupportV1.mutation(51_373)
        )
        let supersedeMutation = try EvidenceAssuranceMutationV1(
            workspaceID: fixture.workspaceID,
            expectedRevision: fixture.routineVisibility.revision,
            mutationID: successorVisibility.mutationID,
            postImage: .supersedeVisibility(successorVisibility)
        )
        try successorVisibility.validateSuccessor(of: fixture.routineVisibility)
        try supersedeMutation.validate()
    }

    private func assertC13ImmutableVisibilityManifestAndAttestationSupersessionRetainHistory() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_400)
        let visibilitySuccessor = try EvidenceVisibilityV1(
            visibilityID: C13EvidenceAssuranceTestSupportV1.id(51_401),
            workspaceID: fixture.workspaceID,
            sensitivity: .routine,
            allowedAudiences: [.internalReview, .customerReport],
            effectiveAt: C13EvidenceAssuranceTestSupportV1.fixedDate.addingTimeInterval(7),
            supersedesVisibilityID: fixture.routineVisibility.visibilityID,
            revision: 2,
            mutationID: try C13EvidenceAssuranceTestSupportV1.mutation(51_402)
        )
        try visibilitySuccessor.validateSuccessor(of: fixture.routineVisibility)

        let linkSuccessor = try C13EvidenceAssuranceTestSupportV1.makeLink(
            seed: 51_410,
            workspaceID: fixture.workspaceID,
            visibility: visibilitySuccessor,
            audience: .customerReport,
            evidenceID: fixture.customerLink.evidenceID,
            claimID: fixture.customerLink.claimID,
            supersedesLinkID: fixture.customerLink.linkID,
            revision: 2
        )
        try linkSuccessor.validateSuccessor(of: fixture.customerLink, visibility: visibilitySuccessor)

        let successorPreview = try AssuranceProjectionPreviewV1(
            previewID: C13EvidenceAssuranceTestSupportV1.id(51_420),
            workspaceID: fixture.workspaceID,
            audience: .customerReport,
            snapshotSHA256: fixture.customerPreview.snapshotSHA256,
            projectionVersion: C13EvidenceAssuranceTestSupportV1.projectionVersion,
            links: [linkSuccessor],
            createdAt: C13EvidenceAssuranceTestSupportV1.fixedDate.addingTimeInterval(8)
        )
        let manifestSuccessor = try AssuranceManifestV1(
            manifestID: C13EvidenceAssuranceTestSupportV1.id(51_421),
            preview: successorPreview,
            recordedAt: C13EvidenceAssuranceTestSupportV1.fixedDate.addingTimeInterval(9),
            supersedesManifestID: fixture.customerManifest.manifestID,
            revision: 2,
            mutationID: try C13EvidenceAssuranceTestSupportV1.mutation(51_422)
        )
        try manifestSuccessor.validateSuccessor(of: fixture.customerManifest)

        let linkMutation = try EvidenceAssuranceMutationV1(
            workspaceID: fixture.workspaceID,
            expectedRevision: fixture.customerLink.revision,
            mutationID: linkSuccessor.mutationID,
            postImage: .supersedeLink(linkSuccessor)
        )
        let manifestMutation = try EvidenceAssuranceMutationV1(
            workspaceID: fixture.workspaceID,
            expectedRevision: fixture.customerManifest.revision,
            mutationID: manifestSuccessor.mutationID,
            postImage: .supersedeManifest(
                manifest: manifestSuccessor,
                preview: successorPreview
            )
        )
        try linkMutation.validate()
        try manifestMutation.validate()

        let voidedAttestation = try AttestationV1(
            attestationID: C13EvidenceAssuranceTestSupportV1.id(51_430),
            workspaceID: fixture.workspaceID,
            purpose: fixture.customerAttestation.purpose,
            scope: fixture.customerAttestation.scope,
            manifest: fixture.customerManifest,
            declaredActor: fixture.actor,
            method: fixture.customerAttestation.method,
            action: .voided,
            occurredAt: C13EvidenceAssuranceTestSupportV1.fixedDate.addingTimeInterval(10),
            recordedAt: C13EvidenceAssuranceTestSupportV1.fixedDate.addingTimeInterval(10),
            supersedesAttestationID: fixture.customerAttestation.attestationID,
            revision: 2,
            mutationID: try C13EvidenceAssuranceTestSupportV1.mutation(51_431)
        )
        try voidedAttestation.validateSuccessor(of: fixture.customerAttestation)
        let voidMutation = try EvidenceAssuranceMutationV1(
            workspaceID: fixture.workspaceID,
            expectedRevision: fixture.customerAttestation.revision,
            mutationID: voidedAttestation.mutationID,
            postImage: .voidAttestation(
                value: voidedAttestation,
                manifest: fixture.customerManifest
            )
        )
        try voidMutation.validate()

        XCTAssertEqual(fixture.customerAttestation.action, .recorded)
        XCTAssertEqual(voidedAttestation.action, .voided)
        XCTAssertEqual(voidedAttestation.supersedesAttestationID, fixture.customerAttestation.attestationID)
        XCTAssertEqual(fixture.customerManifest.revision, 1)
        XCTAssertEqual(manifestSuccessor.revision, 2)
        try fixture.customerManifest.validate()
        try fixture.customerAttestation.validate(manifest: fixture.customerManifest)
    }

    func testV23P03C13InterruptionMigrationWritePreviewManifestAndAttestationRecover() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_500)
        let visibilityRow = try EvidenceVisibilityRow(fixture.routineVisibility)
        let linkRow = try ClaimEvidenceLinkRow(fixture.customerLink)
        let manifestRow = try AssuranceManifestRow(fixture.customerManifest)
        let attestationRow = try AttestationRow(fixture.customerAttestation)

        XCTAssertEqual(try visibilityRow.value(), fixture.routineVisibility)
        XCTAssertEqual(try linkRow.value(), fixture.customerLink)
        XCTAssertEqual(try manifestRow.value(), fixture.customerManifest)
        XCTAssertEqual(try attestationRow.value(), fixture.customerAttestation)

        let manifestBytes = try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerManifest)
        let restoredManifest = try EvidenceAssuranceCanonicalCodecV1.decode(
            AssuranceManifestV1.self, from: manifestBytes
        )
        XCTAssertEqual(restoredManifest, fixture.customerManifest)
        XCTAssertEqual(
            try EvidenceAssuranceCanonicalCodecV1.encode(restoredManifest), manifestBytes
        )

        var interruptedBytes = manifestBytes
        interruptedBytes.removeLast()
        XCTAssertThrowsError(
            try EvidenceAssuranceCanonicalCodecV1.decode(AssuranceManifestV1.self, from: interruptedBytes)
        )
        XCTAssertEqual(restoredManifest.includedLinks.count, fixture.customerPreview.includedLinks.count)
        XCTAssertEqual(restoredManifest.excludedLinks.count, fixture.customerPreview.excludedLinks.count)
        try restoredManifest.validateFresh(preview: fixture.customerPreview)
        try assertC13ImmutableVisibilityManifestAndAttestationSupersessionRetainHistory()
    }

    func testV23P03C13RecoveryBackupRestoreCloneForkDeleteEraseSearchReportAndJournalPreserveHistory() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_600)

        XCTAssertEqual(PersistentSchemaV13.versionIdentifier, Schema.Version(13, 0, 0))
        XCTAssertEqual(
            PersistentSchemaReleaseV1.v13.compatibilityID,
            "PERSISTENT_SCHEMA_V13_EVIDENCE_ASSURANCE_HISTORY"
        )
        for rowType in [
            ObjectIdentifier(EvidenceVisibilityRow.self),
            ObjectIdentifier(ClaimEvidenceLinkRow.self),
            ObjectIdentifier(AssuranceManifestRow.self),
            ObjectIdentifier(AttestationRow.self),
        ] {
            XCTAssertTrue(PersistentSchemaV13.models.contains { ObjectIdentifier($0) == rowType })
        }
        XCTAssertEqual(AttestationMethodV1.allCases.count, 2)
        XCTAssertTrue(AttestationMethodV1.allCases.contains(.explicitLocalConfirmation))
        XCTAssertTrue(AttestationMethodV1.allCases.contains(.importedExternalEvidence))

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: C13EvidenceAssuranceTestSupportV1.corpusURL())
            ) as? [String: Any]
        )
        XCTAssertEqual(root["cardID"] as? String, "V23-P03-C13")
        XCTAssertEqual(root["synthetic"] as? Bool, true)
        XCTAssertEqual(root["containsCustomerData"] as? Bool, false)
        XCTAssertEqual(root["containsSecrets"] as? Bool, false)
        let claims = try XCTUnwrap(root["claims"] as? [String: Any])
        XCTAssertTrue(claims.values.allSatisfy { ($0 as? Bool) == false })

        let attestationJSON = String(
            data: try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerAttestation),
            encoding: .utf8
        )!.lowercased()
        for prohibited in ["legal signature", "nonrepudiation", "cloud account", "remote delivery"] {
            XCTAssertFalse(attestationJSON.contains(prohibited), prohibited)
        }

        let persistedRows: [(Data, Data)] = [
            (
                try EvidenceAssuranceCanonicalCodecV1.encode(fixture.routineVisibility),
                try EvidenceAssuranceCanonicalCodecV1.encode(try EvidenceVisibilityRow(fixture.routineVisibility).value())
            ),
            (
                try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerLink),
                try EvidenceAssuranceCanonicalCodecV1.encode(try ClaimEvidenceLinkRow(fixture.customerLink).value())
            ),
            (
                try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerManifest),
                try EvidenceAssuranceCanonicalCodecV1.encode(try AssuranceManifestRow(fixture.customerManifest).value())
            ),
            (
                try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerAttestation),
                try EvidenceAssuranceCanonicalCodecV1.encode(try AttestationRow(fixture.customerAttestation).value())
            )
        ]
        XCTAssertTrue(persistedRows.allSatisfy { $0.0 == $0.1 })
        XCTAssertEqual(persistedRows.count, 4)
        XCTAssertEqual(fixture.customerManifest.sourcePreviewID, fixture.customerPreview.previewID)
        XCTAssertEqual(fixture.customerAttestation.scope.scopeID, fixture.customerManifest.manifestID)
    }

    private func assertCanonicalRoundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try EvidenceAssuranceCanonicalCodecV1.encode(value)
        let decoded = try EvidenceAssuranceCanonicalCodecV1.decode(T.self, from: data)
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(try EvidenceAssuranceCanonicalCodecV1.encode(decoded), data)
    }
}

extension V9_27EvidenceAssuranceTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension V9_27EvidenceAssuranceTests {
    func testV23P03C14ClosureEvidenceUsesTypedC13BoundaryReferences() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_227)
        XCTAssertEqual(fixture.closureEvidence.count, 2)
        XCTAssertTrue(fixture.closureEvidence.contains { $0.kind == .completedActivitySnapshot })
        XCTAssertTrue(fixture.closureEvidence.contains { $0.kind == .verifiedRecheck })
        XCTAssertEqual(fixture.actions[3].closureEvidence, fixture.closureEvidence)
        XCTAssertEqual(fixture.actions[3].verifier?.responsibility, .verifiedBy)
    }
}

private final class C48PortableReviewV927EvidenceAssuranceTests: XCTestCase {
    func testC48ReviewResponseIsNotEvidenceAssurance() {
        XCTAssertTrue(C48PortableReviewEvidenceAssuranceBoundaryV1.reviewResponseIsNotEvidenceAssurance)
        XCTAssertFalse(C48PortableReviewEvidenceAssuranceBoundaryV1.capabilityProofBytesBecomeEvidence)
        XCTAssertTrue(C48PortableReviewEvidenceAssuranceBoundaryV1.existingAssuranceManifestRemainsCanonical)
    }
}

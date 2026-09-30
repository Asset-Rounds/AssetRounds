import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Constructed value fixtures exercise the C20/report boundary only. They do
/// not establish store capture, pixel transformation, or human approval.
final class V23ActivityEvidenceProjectionTests: XCTestCase {
    func testV23P03C20CompletedProjectionAcceptsDistinctFieldAndApprovedMediaDigests() throws {
        let fixture = try makeFixture()
        let projection = try makeProjection(fixture)
        let card = try makeCard(fixture)

        // Independently calculated from the literal PNG and canonical field
        // bytes below, rather than copied from the constructed projection.
        XCTAssertEqual(fixture.manifest.sourceSHA256,
                       "e878950f8091ec010cf5cc723bdea027a8539cf7147cfea199c2f666232dcd4e")
        XCTAssertEqual(projection.derivativeSHA256,
                       "c47dd9465c00e9a0c8b85e9ea58d3034a0d23b9cf926113602f3460752a4eb96")
        XCTAssertEqual(card.privacyTransformedSHA256,
                       "6568d0703f5568e9820efcfe6ed6223b2f72f2e6b11e6261b06b40de31349907")
        XCTAssertNotEqual(card.privacyTransformedSHA256, projection.derivativeSHA256)
        XCTAssertNotEqual(projection.sourceSHA256, projection.derivativeSHA256)
        XCTAssertEqual(card.fields.map(\.fieldID), ["caption", "role"])
        XCTAssertEqual(card.outputReferences.map(\.contentSHA256), [projection.derivativeSHA256])
        XCTAssertEqual(card.reviewedMarkup.sourcePrivacyDigest, card.privacyTransformedSHA256)
        XCTAssertEqual(try card.c20ValidatePrivacyTransformProjection(projection), projection)

        let decodedCard = try JSONDecoder().decode(
            EvidenceDetailCardV1.self, from: canonicalBytes(card)
        )
        let decodedProjection = try JSONDecoder().decode(
            PrivacyTransformReportProjectionV1.self, from: canonicalBytes(projection)
        )
        XCTAssertEqual(decodedCard, card)
        XCTAssertEqual(decodedProjection, projection)
        XCTAssertEqual(try decodedCard.c20ValidatePrivacyTransformProjection(decodedProjection), projection)
    }

    func testV23P03C20CompletedProjectionRejectsUnapprovedAndMixedMedia() throws {
        let fixture = try makeFixture()
        let projection = try makeProjection(fixture)
        let otherMedia = try contentReference(
            workspace: fixture.workspace,
            contentID: "c20-unapproved-derivative",
            bytes: try XCTUnwrap(Data(base64Encoded: Self.unapprovedPNG)),
            role: .derivative
        )
        XCTAssertEqual(otherMedia.digests.digest(for: .sha256)?.hexadecimalValue,
                       "b1ff9c8ea3a780bad09b346c423d2d0e46815926879b18e841d928376a946640")
        let wrong = try makeCard(fixture, references: [otherMedia])
        let mixed = try makeCard(fixture, references: [fixture.derivative, otherMedia])
        try wrong.validate()
        try mixed.validate()
        XCTAssertThrowsError(try wrong.c20ValidatePrivacyTransformProjection(projection)) {
            XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .privacyViolation)
        }
        XCTAssertThrowsError(try mixed.c20ValidatePrivacyTransformProjection(projection)) {
            XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .privacyViolation)
        }
    }

    func testV23P03C20CompletedProjectionRejectsOriginalAndMissingOutputReferences() throws {
        let fixture = try makeFixture()
        let projection = try makeProjection(fixture)
        let empty = try makeCard(fixture, references: [])
        try empty.validate()
        XCTAssertThrowsError(try empty.c20ValidatePrivacyTransformProjection(projection)) {
            XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .privacyViolation)
        }
        XCTAssertThrowsError(try makeCard(fixture, references: [fixture.original])) {
            XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .privacyViolation)
        }

        // Internal cards can contain originals, so this reaches the C20 helper
        // with a valid card and an audience-matched approved projection.
        let internalFixture = try makeFixture(audience: .internalReview)
        let internalProjection = try makeProjection(internalFixture)
        let internalCard = try makeCard(
            internalFixture, references: [internalFixture.original], audience: .internalUse
        )
        try internalCard.validate()
        XCTAssertThrowsError(try internalCard.c20ValidatePrivacyTransformProjection(internalProjection)) {
            XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .privacyViolation)
        }

        // Even an original-role reference carrying the exact approved bytes is
        // excluded; matching the digest alone does not establish its role.
        let mislabeled = try contentReference(
            workspace: internalFixture.workspace,
            contentID: "c20-original-role-approved-bytes",
            bytes: internalFixture.derivativeBytes,
            role: .immutableOriginal
        )
        let sameDigestOriginal = try makeCard(
            internalFixture, references: [mislabeled], audience: .internalUse
        )
        XCTAssertEqual(sameDigestOriginal.outputReferences[0].contentSHA256,
                       internalProjection.derivativeSHA256)
        XCTAssertThrowsError(try sameDigestOriginal.c20ValidatePrivacyTransformProjection(internalProjection)) {
            XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .privacyViolation)
        }
    }

    func testV23P03C20CompletedProjectionRejectsWrongWorkspaceAndAudience() throws {
        let fixture = try makeFixture()
        let projection = try makeProjection(fixture)
        let otherWorkspace = try makeFixture(workspace: WorkspaceID(rawValue: Self.id(90)))
        let wrongWorkspace = try makeCard(otherWorkspace)
        try wrongWorkspace.validate()
        XCTAssertEqual(wrongWorkspace.outputReferences[0].contentSHA256, projection.derivativeSHA256)
        XCTAssertThrowsError(try wrongWorkspace.c20ValidatePrivacyTransformProjection(projection)) {
            XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .privacyViolation)
        }

        let wrongAudience = try makeCard(fixture, audience: .internalUse)
        try wrongAudience.validate()
        XCTAssertThrowsError(try wrongAudience.c20ValidatePrivacyTransformProjection(projection)) {
            XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .privacyViolation)
        }
        XCTAssertThrowsError(try makeProjection(fixture, requestedAudience: .externalCollaborator)) {
            XCTAssertEqual($0 as? PrivacyTransformReportProjectionFailureV1,
                           .projectionDenied(.wrongAudience))
        }
    }

    func testV23P03C20CompletedProjectionRejectsMissingRejectedStaleAndChangedSource() throws {
        let fixture = try makeFixture()
        XCTAssertThrowsError(try PrivacyTransformReportProjectionV1(
            manifest: fixture.manifest, review: nil, policy: fixture.policy,
            requestedAudience: .customerReport, currentSourceRevision: 1,
            currentSourceSHA256: fixture.manifest.sourceSHA256,
            redactionDeclared: true, now: Self.now
        )) {
            XCTAssertEqual($0 as? PrivacyTransformReportProjectionFailureV1,
                           .projectionDenied(.missingReview))
        }

        let rejected = try makeFixture(reviewDecision: .rejected)
        XCTAssertThrowsError(try makeProjection(rejected)) {
            XCTAssertEqual($0 as? PrivacyTransformReportProjectionFailureV1,
                           .projectionDenied(.rejected))
        }
        let stale = try makeFixture(staleState: .sourceChanged)
        XCTAssertThrowsError(try makeProjection(stale)) {
            XCTAssertEqual($0 as? PrivacyTransformReportProjectionFailureV1,
                           .projectionDenied(.stale))
        }
        XCTAssertThrowsError(try makeProjection(fixture, currentSourceRevision: 2)) {
            XCTAssertEqual($0 as? PrivacyTransformReportProjectionFailureV1,
                           .projectionDenied(.sourceChanged))
        }
        XCTAssertThrowsError(try makeProjection(fixture, currentSourceSHA256: fixture.manifest.derivativeSHA256)) {
            XCTAssertEqual($0 as? PrivacyTransformReportProjectionFailureV1,
                           .projectionDenied(.sourceChanged))
        }
        XCTAssertThrowsError(try makeProjection(fixture, now: Self.now.addingTimeInterval(3_601))) {
            XCTAssertEqual($0 as? PrivacyTransformReportProjectionFailureV1,
                           .projectionDenied(.stale))
        }
        XCTAssertThrowsError(try makeProjection(fixture, redactionDeclared: false)) {
            XCTAssertEqual($0 as? PrivacyTransformReportProjectionFailureV1, .redactionNotDeclared)
        }

        let card = try makeCard(fixture)
        let validProjection = try makeProjection(fixture)
        let alterations: [(String, Any)] = [
            ("reviewDecision", PrivacyReviewDecisionV1.rejected.rawValue),
            ("staleState", PrivacyTransformStaleStateV1.sourceChanged.rawValue),
            ("derivativeSHA256", fixture.manifest.sourceSHA256),
        ]
        for (key, value) in alterations {
            var object = try jsonObject(validProjection)
            object[key] = value
            let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let changed = try JSONDecoder().decode(PrivacyTransformReportProjectionV1.self, from: bytes)
            XCTAssertThrowsError(try card.c20ValidatePrivacyTransformProjection(changed), key) {
                XCTAssertEqual($0 as? PrivacyTransformReportProjectionFailureV1, .invalidValue)
            }
        }
    }

    func testV23P03C20CompletedProjectionRejectsSemanticCardTampering() throws {
        let fixture = try makeFixture()
        let card = try makeCard(fixture)
        let projection = try makeProjection(fixture)
        var fieldsObject = try jsonObject(card)
        var fields = try XCTUnwrap(fieldsObject["fields"] as? [[String: Any]])
        fields[0]["value"] = "Changed after review"
        fieldsObject["fields"] = fields
        try assertCardAdmissionRejects(fieldsObject, projection: projection)

        var markupObject = try jsonObject(card)
        var markup = try XCTUnwrap(markupObject["reviewedMarkup"] as? [String: Any])
        markup["orderedAnnotations"] = ["Changed after review"]
        markupObject["reviewedMarkup"] = markup
        markupObject["annotations"] = ["Changed after review"]
        try assertCardAdmissionRejects(markupObject, projection: projection)

        let plan = try makePlan(fixture)
        // Substituting the media digest for the field digest cannot repair a
        // card: canonical field validation must still reject that old shortcut.
        XCTAssertThrowsError(try EvidenceDetailCardV1(
            cardID: card.cardID, workspaceID: card.workspaceID, evidenceID: card.evidenceID,
            profile: card.profile, privacyTransformedSHA256: projection.derivativeSHA256,
            reviewedMarkup: plan.reviewedMarkup, fields: card.fields,
            outputReferences: card.outputReferences
        )) {
            XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .invalidValue)
        }
    }

    func testV23P03C20CompletedProjectionRebuildsMarkupWithoutChangingReviewedPlan() throws {
        let fixture = try makeFixture()
        let plan = try makePlan(fixture)
        let originalPlanBytes = try canonicalBytes(plan)
        let profile = try makeProfile(audience: .customerSafe)
        let fields = try makeFields()
        let output = try OutputScopedContentReferenceV1(
            outputScopeID: profile.outputScopeID, ordinal: 0, reference: fixture.derivative
        )
        let first = try EvidenceDetailComposerV1.compose(
            cardID: "c20-completed-card", workspaceID: fixture.original.workspaceID,
            evidenceID: "c20-evidence", fields: fields, profile: profile,
            markupID: plan.markupID, annotations: plan.reviewedMarkup.orderedAnnotations,
            referenceLabels: plan.reviewedMarkup.orderedReferenceLabels, outputReferences: [output]
        )
        let decodedPlan = try JSONDecoder().decode(
            EvidenceReviewedMarkupPlanV1.self, from: originalPlanBytes
        )
        try decodedPlan.validate()
        let rebuilt = try EvidenceDetailComposerV1.compose(
            cardID: first.cardID, workspaceID: first.workspaceID, evidenceID: first.evidenceID,
            fields: fields, profile: profile, markupID: decodedPlan.markupID,
            annotations: decodedPlan.reviewedMarkup.orderedAnnotations,
            referenceLabels: decodedPlan.reviewedMarkup.orderedReferenceLabels,
            outputReferences: [output]
        )
        XCTAssertEqual(first, rebuilt)
        XCTAssertEqual(try canonicalBytes(first), try canonicalBytes(rebuilt))
        XCTAssertEqual(first.annotations, ["Current observed detail"])
        XCTAssertEqual(first.referenceLabels, ["Reviewed derivative"])
        XCTAssertEqual(first.annotations, plan.reviewedMarkup.orderedAnnotations)
        XCTAssertEqual(first.referenceLabels, plan.reviewedMarkup.orderedReferenceLabels)
        XCTAssertEqual(plan.reviewedMarkup.sourcePrivacyDigest, fixture.manifest.derivativeSHA256)
        XCTAssertEqual(first.reviewedMarkup.sourcePrivacyDigest, first.privacyTransformedSHA256)
        XCTAssertNotEqual(first.reviewedMarkup, plan.reviewedMarkup)
        XCTAssertEqual(decodedPlan, plan)
        XCTAssertEqual(try canonicalBytes(plan), originalPlanBytes)
        XCTAssertEqual(try canonicalBytes(decodedPlan), originalPlanBytes)
        XCTAssertEqual(plan.privacyManifest, fixture.manifest)
        XCTAssertEqual(plan.privacyReview, fixture.review)
        XCTAssertEqual(plan.privacyPolicy, fixture.policy)
        XCTAssertEqual(plan.source, fixture.original)
        let projection = try makeProjection(fixture)
        XCTAssertEqual(try rebuilt.c20ValidatePrivacyTransformProjection(projection), projection)
    }

    private struct Fixture {
        let workspace: WorkspaceID
        let derivativeBytes: Data
        let original: ContentReferenceV1
        let derivative: ContentReferenceV1
        let policy: PrivacyTransformPolicyV1
        let manifest: PrivacyTransformManifestV1
        let review: PrivacyReviewReceiptV1
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let originalPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC"
    private static let derivativePNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC"
    private static let unapprovedPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"

    private static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c2060000-0000-4000-8000-%012x", slot))!
    }

    private func contentReference(
        workspace: WorkspaceID,
        contentID: String,
        bytes: Data,
        role: ContentByteRoleV1
    ) throws -> ContentReferenceV1 {
        let workspaceText = workspace.rawValue.uuidString.lowercased()
        let observed = try ContentIntegrityV1.observe(
            workspaceID: workspaceText, contentID: contentID, data: bytes, mediaType: "image/png"
        )
        return try ContentReferenceV1(
            workspaceID: workspaceText, contentID: contentID,
            byteLength: Int64(bytes.count), mediaType: "image/png", digests: observed.digests,
            byteRole: role, createdAt: "2027-01-15T08:00:00.000Z"
        )
    }

    private func makeFixture(
        workspace: WorkspaceID? = nil,
        audience: EvidenceAudienceV1 = .customerReport,
        staleState: PrivacyTransformStaleStateV1 = .current,
        reviewDecision: PrivacyReviewDecisionV1 = .approved
    ) throws -> Fixture {
        let workspace = workspace ?? WorkspaceID(rawValue: Self.id(1))
        let mutation = try MutationIDV1(rawValue: Self.id(2))
        let originalBytes = try XCTUnwrap(Data(base64Encoded: Self.originalPNG))
        let derivativeBytes = try XCTUnwrap(Data(base64Encoded: Self.derivativePNG))
        let original = try contentReference(
            workspace: workspace, contentID: "c20-original", bytes: originalBytes, role: .immutableOriginal
        )
        let derivative = try contentReference(
            workspace: workspace, contentID: "c20-derivative", bytes: derivativeBytes, role: .derivative
        )
        let sourceSHA = try XCTUnwrap(original.digests.digest(for: .sha256)?.hexadecimalValue)
        let derivativeSHA = try XCTUnwrap(derivative.digests.digest(for: .sha256)?.hexadecimalValue)
        let authorReference = try LocalActorReferenceV1(
            actorReferenceID: Self.id(10), workspaceID: workspace, displayName: "Fixture operator"
        )
        let author = try ActorSnapshotV1(
            snapshotID: Self.id(11), workspaceID: workspace, actor: authorReference,
            responsibility: .performedBy, displayNameAtTime: "Fixture operator", capturedAt: Self.now
        )
        let reviewerReference = try LocalActorReferenceV1(
            actorReferenceID: Self.id(12), workspaceID: workspace, displayName: "Fixture reviewer"
        )
        let reviewer = try ActorSnapshotV1(
            snapshotID: Self.id(13), workspaceID: workspace, actor: reviewerReference,
            responsibility: .reviewedBy, displayNameAtTime: "Fixture reviewer", capturedAt: Self.now
        )
        let policy = try PrivacyTransformPolicyV1(
            policyID: Self.id(20), workspaceID: workspace, purpose: "Fixture privacy projection",
            audience: audience, allowedTransformKinds: [.solidFill], allowedReasons: [.person],
            maximumAgeSeconds: 3_600, effectiveAt: Self.now, mutationID: mutation
        )
        let bounds = try PrivacyIntegerRectV1(x: 0, y: 0, width: 1_000_000, height: 1_000_000)
        let region = try PrivacyRegionV1(
            regionID: Self.id(30), workspaceID: workspace, sourceContentID: original.contentID,
            sourceRevision: 1, sourceSHA256: sourceSHA, coordinateSpace: .normalizedImage,
            orientation: .up, sourceBounds: bounds, transformKind: .solidFill, reason: .person,
            author: author, order: 0, authoredAt: Self.now, mutationID: mutation
        )
        let sanitation = try PrivacyMetadataSanitationEvidenceV1(
            sanitizerID: "fixture-sanitizer", sanitizerVersion: "1", result: .complete
        )
        let manifest = try PrivacyTransformManifestV1(
            manifestID: Self.id(40), workspaceID: workspace, original: original,
            sourceRevision: 1, sourceSHA256: sourceSHA, derivative: derivative,
            derivativeSHA256: derivativeSHA, policy: policy, orderedRegions: [region],
            rendererID: "fixture-renderer", rendererVersion: "1", metadataSanitation: sanitation,
            staleState: staleState, renderedAt: Self.now, mutationID: mutation
        )
        let review = try PrivacyReviewReceiptV1(
            receiptID: Self.id(50), workspaceID: workspace, manifest: manifest, policy: policy,
            reviewer: reviewer, decision: reviewDecision, rationale: "Constructed boundary fixture",
            reviewedAt: Self.now, mutationID: mutation
        )
        return Fixture(
            workspace: workspace, derivativeBytes: derivativeBytes, original: original,
            derivative: derivative, policy: policy, manifest: manifest, review: review
        )
    }

    private func makeProjection(
        _ fixture: Fixture,
        requestedAudience: EvidenceAudienceV1? = nil,
        currentSourceRevision: UInt64 = 1,
        currentSourceSHA256: String? = nil,
        redactionDeclared: Bool = true,
        now: Date? = nil
    ) throws -> PrivacyTransformReportProjectionV1 {
        try PrivacyTransformReportProjectionV1(
            manifest: fixture.manifest, review: fixture.review, policy: fixture.policy,
            requestedAudience: requestedAudience ?? fixture.policy.audience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256 ?? fixture.manifest.sourceSHA256,
            redactionDeclared: redactionDeclared, now: now ?? Self.now
        )
    }

    private func makeProfile(audience: ReportAudienceV1) throws -> EvidenceDetailCardProfileV1 {
        let privacyPolicy = try AudiencePrivacyPolicyV1(
            policyID: "c20-audience-policy", policyVersion: 1, audience: audience,
            prohibitedCanaries: ["private-canary"]
        )
        return try EvidenceDetailCardProfileV1(
            profileID: "c20-detail-profile", profileRelease: 1, audience: audience,
            outputScopeID: "c20-completed-output", privacyTransformID: "c20-field-transform",
            privacyTransformVersion: 1, markupProfileID: "c20-markup-profile",
            markupProfileVersion: 1, localeIdentifier: "en-US",
            displayProfileID: "c20-display-profile", rendererVersion: "c20-renderer-1",
            audiencePrivacyPolicy: privacyPolicy, includedFieldIDs: ["caption", "private-note", "role"],
            limitationsText: "This detail does not verify capture time, location, or person."
        )
    }

    private func makeFields() throws -> [EvidenceDetailFieldV1] {
        let caption = try EvidenceDetailFieldV1(
            fieldID: "caption", label: "Caption", value: "Reviewed detail", sensitivity: .audienceSafe
        )
        let privateNote = try EvidenceDetailFieldV1(
            fieldID: "private-note", label: "Private note", value: "private-canary", sensitivity: .privateNote
        )
        let role = try EvidenceDetailFieldV1(
            fieldID: "role", label: "Role", value: "Detail", sensitivity: .audienceSafe
        )
        return [caption, privateNote, role]
    }

    private func makeCard(
        _ fixture: Fixture,
        references: [ContentReferenceV1]? = nil,
        audience: ReportAudienceV1 = .customerSafe
    ) throws -> EvidenceDetailCardV1 {
        let profile = try makeProfile(audience: audience)
        let references = references ?? [fixture.derivative]
        var outputs: [OutputScopedContentReferenceV1] = []
        for (ordinal, reference) in references.enumerated() {
            outputs.append(try OutputScopedContentReferenceV1(
                outputScopeID: profile.outputScopeID, ordinal: ordinal, reference: reference
            ))
        }
        outputs.sort()
        let labels = Array(repeating: "Reviewed derivative", count: outputs.count)
        return try EvidenceDetailComposerV1.compose(
            cardID: "c20-completed-card", workspaceID: fixture.original.workspaceID,
            evidenceID: "c20-evidence", fields: makeFields(), profile: profile,
            markupID: "c20-reviewed-markup", annotations: ["Current observed detail"],
            referenceLabels: labels, outputReferences: outputs
        )
    }

    private func makePlan(_ fixture: Fixture) throws -> EvidenceReviewedMarkupPlanV1 {
        let old = try EvidenceAnnotationV1(
            annotationID: "annotation-old", action: .add, text: "Superseded observation"
        )
        let removal = try EvidenceAnnotationV1(
            annotationID: "annotation-remove", action: .remove,
            text: "Removed superseded observation", supersedesAnnotationID: old.annotationID
        )
        let current = try EvidenceAnnotationV1(
            annotationID: "annotation-current", action: .add, text: "Current observed detail"
        )
        return try EvidenceReviewedMarkupPlanV1(
            markupID: "c20-reviewed-markup", workspaceID: fixture.workspace, source: fixture.original,
            privacyPolicy: fixture.policy, privacyManifest: fixture.manifest, privacyReview: fixture.review,
            orderedAnnotations: [old, removal, current], orderedReferenceLabels: ["Reviewed derivative"]
        )
    }

    private func canonicalBytes<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: canonicalBytes(value)) as? [String: Any])
    }

    private func assertCardAdmissionRejects(
        _ object: [String: Any],
        projection: PrivacyTransformReportProjectionV1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertThrowsError(try {
            let changed = try JSONDecoder().decode(EvidenceDetailCardV1.self, from: bytes)
            _ = try changed.c20ValidatePrivacyTransformProjection(projection)
        }(), file: file, line: line)
    }
}

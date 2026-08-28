import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C20PrivacyTransformTestFailure: Error {
    case malformedObject
}

enum C20PrivacyTransformTestSupport {
    struct Fixture {
        let workspace: WorkspaceID
        let mutationID: MutationIDV1
        let capturedAt: Date
        let originalBytes: Data
        let derivativeBytes: Data
        let originalObserved: ContentObservedBytesV1
        let derivativeObserved: ContentObservedBytesV1
        let original: ContentReferenceV1
        let derivative: ContentReferenceV1
        let policy: PrivacyTransformPolicyV1
        let author: ActorSnapshotV1
        let reviewer: ActorSnapshotV1
        let regions: [PrivacyRegionV1]
        let manifest: PrivacyTransformManifestV1
        let approvedReview: PrivacyReviewReceiptV1
        let rejectedReview: PrivacyReviewReceiptV1
        let locator: ContentLocatorV1
        let provenance: ContentDerivativeProvenanceV1
        let originalProvenance: ContentOriginalProvenanceV1
        let bundle: PrivacyTransformPublicationBundleV1
        let policyRow: PrivacyTransformPolicyRow
        let regionRows: [PrivacyRegionRow]
        let manifestRow: PrivacyTransformManifestRow
        let reviewRow: PrivacyReviewReceiptRow
        let backupRecords: [V19BackupPrivacyTransformRecordV1]
    }

    static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
    static let fixedInstant = "2026-08-28T00:00:00.000Z"
    static let canonicalMutationReceiptSHA256 = String(repeating: "b", count: 64)

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c2000000-0000-4000-8000-%012x", slot))!
    }

    static func digest(_ character: Character = "a") -> String {
        String(repeating: character, count: 64)
    }

    static func makeCanonicalMutationReceipt(for fixture: Fixture) throws -> MutationReceiptV1 {
        let mutation = PrivacyTransformMutationV1.publish(
            policy: fixture.policy,
            regions: fixture.regions,
            manifest: fixture.manifest
        )
        try mutation.validate()

        let generationID = id(90)
        let writerInstanceID = id(91)
        let replicaID = ReplicaID(rawValue: id(92))
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: fixture.workspace,
            replicaID: replicaID
        )
        let concurrencyIdentities = try mutation.concurrencyIdentities
        let expectedRevision = try WorkspaceExpectedRevisionV1(
            workspaceID: fixture.workspace,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            workspaceRevision: 0,
            entityRevisions: concurrencyIdentities.map {
                WorkspaceEntityRevisionV1(identity: $0, revision: 0)
            }
        )
        let envelope = try MutationEnvelopeV1(
            request: WorkspaceMutationRequestV1(
                mutationID: fixture.mutationID,
                expectedRevision: expectedRevision,
                command: .applyPrivacyTransform(mutation)
            ),
            identity: identity
        )
        let postImages = try mutation.mutationPostImages
        let resultingRevision = try MutationPortableExpectedRevisionV1(
            WorkspaceRevisionV1(
                workspaceID: fixture.workspace,
                generationID: generationID,
                writerInstanceID: writerInstanceID,
                revision: 1,
                entityRevisions: try postImages.map {
                    WorkspaceEntityRevisionV1(identity: try $0.identity, revision: $0.revision)
                }
            )
        )
        return try MutationReceiptV1(
            identity: MutationReceiptIdentityV1(
                workspaceID: fixture.workspace,
                replicaID: replicaID,
                localSequence: 1
            ),
            envelope: envelope,
            resultingRevision: resultingRevision,
            postImages: postImages,
            committedAt: fixedDate.addingTimeInterval(3)
        )
    }

    static func makeFixture() throws -> Fixture {
        let workspace = WorkspaceID(rawValue: id(1))
        let mutationID = try MutationIDV1(rawValue: id(2))
        let capturedAt = fixedDate
        let originalBytes = Data("c20 immutable original bytes".utf8)
        let derivativeBytes = Data("c20 redacted derivative bytes".utf8)
        let originalObserved = try ContentIntegrityV1.observe(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            contentID: "c20-original",
            data: originalBytes,
            mediaType: "image/jpeg"
        )
        let derivativeObserved = try ContentIntegrityV1.observe(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            contentID: "c20-derivative",
            data: derivativeBytes,
            mediaType: "image/jpeg"
        )
        let original = try ContentReferenceV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            contentID: "c20-original",
            byteLength: Int64(originalBytes.count),
            mediaType: "image/jpeg",
            digests: originalObserved.digests,
            byteRole: .immutableOriginal,
            createdAt: fixedInstant
        )
        let derivative = try ContentReferenceV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            contentID: "c20-derivative",
            byteLength: Int64(derivativeBytes.count),
            mediaType: "image/jpeg",
            digests: derivativeObserved.digests,
            byteRole: .derivative,
            createdAt: fixedInstant
        )
        let sourceSHA256 = try XCTUnwrap(
            originalObserved.digests.digest(for: .sha256)?.hexadecimalValue
        )
        let derivativeSHA256 = try XCTUnwrap(
            derivativeObserved.digests.digest(for: .sha256)?.hexadecimalValue
        )
        let authorReference = try LocalActorReferenceV1(
            actorReferenceID: id(10), workspaceID: workspace, displayName: "C20 operator"
        )
        let author = try ActorSnapshotV1(
            snapshotID: id(11), workspaceID: workspace, actor: authorReference,
            responsibility: .performedBy, displayNameAtTime: "C20 operator", capturedAt: capturedAt
        )
        let reviewerReference = try LocalActorReferenceV1(
            actorReferenceID: id(12), workspaceID: workspace, displayName: "C20 reviewer"
        )
        let reviewer = try ActorSnapshotV1(
            snapshotID: id(13), workspaceID: workspace, actor: reviewerReference,
            responsibility: .reviewedBy, displayNameAtTime: "C20 reviewer",
            capturedAt: capturedAt.addingTimeInterval(1)
        )
        let policy = try PrivacyTransformPolicyV1(
            policyID: id(20), workspaceID: workspace, purpose: "customer-safe redaction",
            audience: .customerReport,
            allowedTransformKinds: [.blur, .solidFill, .pixelate],
            allowedReasons: [.vehicleIdentifier, .person, .confidentialInformation,
                             .identifyingMark, .unrelatedPrivateDetail],
            maximumAgeSeconds: 3_600, effectiveAt: capturedAt, mutationID: mutationID
        )
        let regions = try [
            PrivacyRegionV1(
                regionID: id(30), workspaceID: workspace, sourceContentID: original.contentID,
                sourceRevision: 1, sourceSHA256: sourceSHA256,
                coordinateSpace: .normalizedImage, orientation: .up,
                sourceBounds: try PrivacyIntegerRectV1(x: 100_000, y: 200_000, width: 250_000, height: 200_000),
                transformKind: .blur, reason: .person, author: author, order: 0,
                authoredAt: capturedAt, mutationID: mutationID
            ),
            PrivacyRegionV1(
                regionID: id(31), workspaceID: workspace, sourceContentID: original.contentID,
                sourceRevision: 1, sourceSHA256: sourceSHA256,
                coordinateSpace: .normalizedImage, orientation: .up,
                sourceBounds: try PrivacyIntegerRectV1(x: 200_000, y: 300_000, width: 200_000, height: 200_000),
                transformKind: .pixelate, reason: .identifyingMark, author: author, order: 1,
                authoredAt: capturedAt, mutationID: mutationID
            ),
            PrivacyRegionV1(
                regionID: id(32), workspaceID: workspace, sourceContentID: original.contentID,
                sourceRevision: 1, sourceSHA256: sourceSHA256,
                coordinateSpace: .normalizedImage, orientation: .up,
                sourceBounds: try PrivacyIntegerRectV1(x: 700_000, y: 100_000, width: 100_000, height: 150_000),
                transformKind: .solidFill, reason: .confidentialInformation, author: author, order: 2,
                authoredAt: capturedAt, mutationID: mutationID
            )
        ]
        let manifest = try PrivacyTransformManifestV1(
            manifestID: id(40), workspaceID: workspace, original: original, sourceRevision: 1,
            sourceSHA256: sourceSHA256, derivative: derivative, derivativeSHA256: derivativeSHA256,
            policy: policy, orderedRegions: regions, rendererID: "c20-privacy-renderer",
            rendererVersion: "1", metadataSanitation: try PrivacyMetadataSanitationEvidenceV1(
                sanitizerID: "c20-metadata-sanitizer", sanitizerVersion: "1", result: .complete
            ), renderedAt: capturedAt, mutationID: mutationID
        )
        let approvedReview = try PrivacyReviewReceiptV1(
            receiptID: id(50), workspaceID: workspace, manifest: manifest, policy: policy,
            reviewer: reviewer, decision: .approved, rationale: "Reviewed redaction regions",
            reviewedAt: capturedAt.addingTimeInterval(2), mutationID: mutationID
        )
        let rejectedReview = try PrivacyReviewReceiptV1(
            receiptID: id(51), workspaceID: workspace, manifest: manifest, policy: policy,
            reviewer: reviewer, decision: .rejected, rationale: "Rejected for rework",
            reviewedAt: capturedAt.addingTimeInterval(2), mutationID: mutationID
        )
        let derivativeDigest = try XCTUnwrap(
            derivativeObserved.digests.digest(for: .sha256)
        )
        let locator = try ContentLocatorV1(
            locatorID: "c20-derivative-locator", workspaceID: derivative.workspaceID,
            contentID: derivative.contentID, locatorRevision: 1, contentDigest: derivativeDigest,
            expectedByteLength: derivative.byteLength
        )
        let originalDigest = try XCTUnwrap(originalObserved.digests.digest(for: .sha256))
        let provenance = try ContentDerivativeProvenanceV1(
            provenanceID: "c20-privacy-provenance", workspaceID: derivative.workspaceID,
            sources: [try ContentSourceBindingV1(contentID: original.contentID, digest: originalDigest)],
            derivativeContentID: derivative.contentID, derivativeDigest: derivativeDigest,
            transform: .privacy(try PrivacyDerivativeV1(
                privacyManifestID: manifest.manifestID,
                privacyManifestSHA256: manifest.manifestSHA256,
                rendererID: manifest.rendererID, rendererVersion: manifest.rendererVersion
            )), metadataSanitizerID: manifest.metadataSanitation.sanitizerID,
            metadataSanitizerVersion: manifest.metadataSanitation.sanitizerVersion,
            createdAt: fixedInstant
        )
        let originalProvenance = try ContentOriginalProvenanceV1(
            provenanceID: "c20-original-provenance", workspaceID: original.workspaceID,
            contentID: original.contentID, contentDigest: originalDigest,
            origin: .localImport, recordedAt: fixedInstant
        )
        let bundle = PrivacyTransformPublicationBundleV1(
            policy: policy, manifest: manifest,
            derivativeBytes: derivativeBytes, derivativeLocator: locator, provenance: provenance
        )
        let policyRow = try PrivacyTransformPolicyRow(policy)
        let regionRows = try regions.map(PrivacyRegionRow.init)
        let manifestRow = try PrivacyTransformManifestRow(manifest)
        let reviewRow = try PrivacyReviewReceiptRow(approvedReview)
        let backupRecords = [
            V19BackupPrivacyTransformRecordV1(
                kind: .policy, id: policy.policyID, workspaceID: workspace.rawValue,
                revision: policy.revision, canonicalData: try PrivacyTransformCanonicalCodecV1.encode(policy)
            ),
            V19BackupPrivacyTransformRecordV1(
                kind: .region, id: regions[0].regionID, workspaceID: workspace.rawValue,
                revision: regions[0].revision, canonicalData: try PrivacyTransformCanonicalCodecV1.encode(regions[0])
            ),
            V19BackupPrivacyTransformRecordV1(
                kind: .manifest, id: manifest.manifestID, workspaceID: workspace.rawValue,
                revision: manifest.revision, canonicalData: try PrivacyTransformCanonicalCodecV1.encode(manifest)
            ),
            V19BackupPrivacyTransformRecordV1(
                kind: .reviewReceipt, id: approvedReview.receiptID, workspaceID: workspace.rawValue,
                revision: approvedReview.revision, canonicalData: try PrivacyTransformCanonicalCodecV1.encode(approvedReview)
            )
        ]
        return Fixture(
            workspace: workspace, mutationID: mutationID, capturedAt: capturedAt,
            originalBytes: originalBytes, derivativeBytes: derivativeBytes,
            originalObserved: originalObserved, derivativeObserved: derivativeObserved,
            original: original, derivative: derivative, policy: policy, author: author,
            reviewer: reviewer, regions: regions, manifest: manifest,
            approvedReview: approvedReview, rejectedReview: rejectedReview, locator: locator,
            provenance: provenance, originalProvenance: originalProvenance, bundle: bundle,
            policyRow: policyRow, regionRows: regionRows, manifestRow: manifestRow,
            reviewRow: reviewRow, backupRecords: backupRecords
        )
    }

    static func manifest(
        from fixture: Fixture,
        staleState: PrivacyTransformStaleStateV1
    ) throws -> PrivacyTransformManifestV1 {
        try PrivacyTransformManifestV1(
            manifestID: fixture.manifest.manifestID, workspaceID: fixture.workspace,
            original: fixture.original, sourceRevision: fixture.manifest.sourceRevision,
            sourceSHA256: fixture.manifest.sourceSHA256, derivative: fixture.derivative,
            derivativeSHA256: fixture.manifest.derivativeSHA256, policy: fixture.policy,
            orderedRegions: fixture.regions, rendererID: fixture.manifest.rendererID,
            rendererVersion: fixture.manifest.rendererVersion,
            metadataSanitation: fixture.manifest.metadataSanitation, staleState: staleState,
            renderedAt: fixture.manifest.renderedAt, mutationID: fixture.mutationID
        )
    }

    static func forgedReview(
        _ review: PrivacyReviewReceiptV1,
        receiptSHA256: String
    ) throws -> PrivacyReviewReceiptV1 {
        guard var object = try JSONSerialization.jsonObject(
            with: PrivacyTransformCanonicalCodecV1.encode(review)
        ) as? [String: Any] else { throw C20PrivacyTransformTestFailure.malformedObject }
        object["receiptSHA256"] = receiptSHA256
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try PrivacyTransformCanonicalCodecV1.decode(PrivacyReviewReceiptV1.self, from: data)
    }
}

private struct C20CorpusSelectorV1: Decodable {
    let id: String
    let selector: String
    let focus: String
}

private struct C20CorpusFlagsV1: Decodable {
    let native: Bool
    let hosted: Bool
    let adoption: Bool
    let acceptance: Bool
    let release: Bool
}

private struct C20PrivacyTransformCorpusV1: Decodable {
    let schema: String
    let schemaVersion: Int
    let corpusID: String
    let cardID: String
    let ordinal: Int
    let phase: String
    let previousCardID: String
    let records: Int
    let recordsSchemaVersion: Int
    let persistentSchemaVersion: Int
    let persistentModelCount: Int
    let evidenceSelectors: [C20CorpusSelectorV1]
    let coverage: [String]
    let evidenceIDs: [String]
    let transformKinds: [String]
    let transformReasons: [String]
    let reviewDecisions: [String]
    let staleStates: [String]
    let projectionDenials: [String]
    let normalizedCoordinateScale: Int
    let coordinateSpaces: [String]
    let orientations: [String]
    let coordinateScaleRatios: [String]
    let atomicInterruptionBoundaries: [String]
    let lifecycleConsumers: [String]
    let privacyExclusions: [String]
    let hostileCases: [String]
    let interruptionCases: [String]
    let recoveryCases: [String]
    let persistentKinds: [String]
    let oldOrNewOnly: Bool
    let retryDisposition: String
    let noSecondWriter: Bool
    let noSecondStore: Bool
    let noRecognitionClaim: Bool
    let noCloudClaim: Bool
    let noLegalClaim: Bool
    let brandExclusion: String
    let forbiddenProductionSymbols: [String]
    let provisionalFlags: C20CorpusFlagsV1
}

actor C20PrivacyPublicationAuthorityForAnchors: PrivacyTransformPublicationAuthorityV1 {
    private var receipts: [MutationIDV1: PrivacyTransformPublicationReceiptV1] = [:]
    private var reviews: [MutationIDV1: PrivacyReviewReceiptV1] = [:]
    private(set) var publishCount = 0
    private(set) var reviewCount = 0

    func publish(_ bundle: PrivacyTransformPublicationBundleV1) async throws -> PrivacyTransformPublicationReceiptV1 {
        publishCount += 1
        let receipt = try PrivacyTransformPublicationReceiptV1(
            bundle: bundle,
            canonicalMutationReceiptSHA256: C20PrivacyTransformTestSupport.canonicalMutationReceiptSHA256
        )
        receipts[bundle.manifest.mutationID] = receipt
        return receipt
    }

    func receipt(for mutationID: MutationIDV1) async throws -> PrivacyTransformPublicationReceiptV1? {
        receipts[mutationID]
    }

    func validatePublicationReceipt(
        _ receipt: PrivacyTransformPublicationReceiptV1,
        bundle: PrivacyTransformPublicationBundleV1
    ) async throws {
        try receipt.validate(
            bundle: bundle,
            expectedCanonicalMutationReceiptSHA256:
                C20PrivacyTransformTestSupport.canonicalMutationReceiptSHA256
        )
    }

    func publishReview(
        _ review: PrivacyReviewReceiptV1,
        manifest: PrivacyTransformManifestV1,
        policy: PrivacyTransformPolicyV1
    ) async throws -> PrivacyReviewReceiptV1 {
        reviewCount += 1
        try review.validate(manifest: manifest, policy: policy)
        reviews[review.mutationID] = review
        return review
    }

    func reviewReceipt(for mutationID: MutationIDV1) async throws -> PrivacyReviewReceiptV1? {
        reviews[mutationID]
    }
}

final class V9_34PrivacyTransformTests: XCTestCase {
    private func loadCorpus() throws -> C20PrivacyTransformCorpusV1 {
        let bundled = Bundle(for: Self.self).url(
            forResource: "V21P03C20PrivacyTransformCorpusV1", withExtension: "json"
        )
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V21/PrivacyTransform/V21P03C20PrivacyTransformCorpusV1.json")
        return try JSONDecoder().decode(
            C20PrivacyTransformCorpusV1.self,
            from: Data(contentsOf: bundled ?? source)
        )
    }

    private func assertCorpus(_ corpus: C20PrivacyTransformCorpusV1) {
        XCTAssertEqual(corpus.schema, "V21P03C20PrivacyTransformCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.corpusID, "V21P03C20PrivacyTransformCorpusV1")
        XCTAssertEqual(corpus.cardID, "V23-P03-C20")
        XCTAssertEqual(corpus.ordinal, 57)
        XCTAssertEqual(corpus.phase, "P03")
        XCTAssertEqual(corpus.previousCardID, "V23-P03-C19")
        XCTAssertEqual(corpus.records, 18)
        XCTAssertEqual(corpus.recordsSchemaVersion, 18)
        XCTAssertEqual(corpus.persistentSchemaVersion, 19)
        XCTAssertEqual(corpus.persistentModelCount, 77)
        XCTAssertEqual(corpus.evidenceSelectors.map(\.selector), ["G", "A", "H", "I", "R"])
        XCTAssertEqual(corpus.evidenceSelectors.map(\.id), [
            "V23-P03-C20-G01", "V23-P03-C20-A01", "V23-P03-C20-H01",
            "V23-P03-C20-I01", "V23-P03-C20-R01"
        ])
        XCTAssertEqual(corpus.evidenceIDs, ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(corpus.coverage, ["GOLDEN", "ALTERNATE", "HOSTILE", "INTERRUPTION", "RECOVERY"])
        XCTAssertEqual(corpus.transformKinds, PrivacyTransformKindV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.transformReasons, PrivacyTransformReasonV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.reviewDecisions, PrivacyReviewDecisionV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.staleStates, PrivacyTransformStaleStateV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.projectionDenials, PrivacyProjectionDenialV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.normalizedCoordinateScale, Int(PrivacyTransformValidationV1.coordinateScale))
        XCTAssertEqual(corpus.coordinateSpaces, PrivacyCoordinateSpaceV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.orientations, PrivacyImageOrientationV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.coordinateScaleRatios, ["1/1", "3/2"])
        XCTAssertEqual(corpus.persistentKinds, ["PRIVACY_TRANSFORM_POLICY_V1", "PRIVACY_REGION_V1", "PRIVACY_TRANSFORM_MANIFEST_V1", "PRIVACY_REVIEW_RECEIPT_V1"])
        XCTAssertEqual(corpus.atomicInterruptionBoundaries, ["POLICY", "REGIONS", "MANIFEST", "REVIEW_RECEIPT"])
        XCTAssertTrue(corpus.lifecycleConsumers.contains("REPORT"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("OPEN_JSON"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("LOCAL_SEARCH"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("SHARE"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("BACKUP"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("RESTORE"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("DELETE"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("ERASE"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("ISOLATED_REPLAY"))
        XCTAssertTrue(corpus.privacyExclusions.contains("CLOUD"))
        XCTAssertTrue(corpus.privacyExclusions.contains("LEGAL"))
        XCTAssertTrue(corpus.hostileCases.contains("missing-review"))
        XCTAssertTrue(corpus.hostileCases.contains("wrong-audience"))
        XCTAssertTrue(corpus.hostileCases.contains("stale-manifest"))
        XCTAssertTrue(corpus.hostileCases.contains("forged-digest"))
        XCTAssertTrue(corpus.interruptionCases.contains("effect-before-receipt"))
        XCTAssertTrue(corpus.recoveryCases.contains("receipt-idempotent-retry"))
        XCTAssertTrue(corpus.oldOrNewOnly)
        XCTAssertEqual(corpus.retryDisposition, "SAME_IMMUTABLE_RECEIPT_OR_SAFE_DISCARD")
        XCTAssertTrue(corpus.noSecondWriter)
        XCTAssertTrue(corpus.noSecondStore)
        XCTAssertTrue(corpus.noRecognitionClaim)
        XCTAssertTrue(corpus.noCloudClaim)
        XCTAssertTrue(corpus.noLegalClaim)
        XCTAssertEqual(corpus.brandExclusion, "BRAND_IMPACT_MANIFEST_IS_EVIDENCE_ONLY")
        XCTAssertTrue(corpus.forbiddenProductionSymbols.contains("URLSession"))
        XCTAssertFalse(corpus.provisionalFlags.native)
        XCTAssertFalse(corpus.provisionalFlags.hosted)
        XCTAssertFalse(corpus.provisionalFlags.adoption)
        XCTAssertFalse(corpus.provisionalFlags.acceptance)
        XCTAssertFalse(corpus.provisionalFlags.release)
    }

    func testV23P03C20G01PrivacyRegionsAreCanonicalNormalizedAndImmutable() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        assertCorpus(try loadCorpus())
        try fixture.policy.validate()
        XCTAssertEqual(fixture.policy.allowedTransformKinds, [.blur, .pixelate, .solidFill])
        XCTAssertEqual(fixture.policy.allowedReasons.map(\.rawValue), fixture.policy.allowedReasons.map(\.rawValue).sorted())
        XCTAssertEqual(PrivacyTransformValidationV1.coordinateScale, 1_000_000)
        XCTAssertEqual(fixture.regions.map(\.order), [0, 1, 2])
        XCTAssertTrue(fixture.regions.allSatisfy { $0.coordinateSpaceVersion == PrivacyCoordinateSpaceV1.normalizedImage.rawValue })
        XCTAssertEqual(Set(fixture.regions.map(\.regionID)).count, fixture.regions.count)
        XCTAssertTrue(fixture.regions[0].bounds.x < fixture.regions[1].bounds.x)
        XCTAssertTrue(fixture.regions[0].bounds.x + fixture.regions[0].bounds.width > fixture.regions[1].bounds.x)

        func coordinateRegion(
            id: UUID,
            space: PrivacyCoordinateSpaceV1,
            orientation: PrivacyImageOrientationV1,
            sourceBounds: PrivacyIntegerRectV1,
            pixelWidth: Int32? = nil,
            pixelHeight: Int32? = nil,
            coordinateScale: PrivacyCoordinateScaleV1 = .identity
        ) throws -> PrivacyRegionV1 {
            try PrivacyRegionV1(
                regionID: id, workspaceID: fixture.workspace,
                sourceContentID: fixture.original.contentID, sourceRevision: 1,
                sourceSHA256: fixture.manifest.sourceSHA256, coordinateSpace: space,
                orientation: orientation, sourceBounds: sourceBounds,
                pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                coordinateScale: coordinateScale, transformKind: .blur, reason: .person,
                author: fixture.author, order: 0, authoredAt: fixture.capturedAt,
                mutationID: fixture.mutationID
            )
        }

        XCTAssertEqual(
            PrivacyCoordinateSpaceV1.allCases.map(\.rawValue),
            ["NORMALIZED_IMAGE_V1", "PIXEL_IMAGE_V1"]
        )
        XCTAssertEqual(PrivacyImageOrientationV1.allCases.count, 8)
        let normalized = try coordinateRegion(
            id: C20PrivacyTransformTestSupport.id(60), space: .normalizedImage,
            orientation: .up,
            sourceBounds: try PrivacyIntegerRectV1(
                x: 100_000, y: 200_000, width: 250_000, height: 200_000
            )
        )
        XCTAssertEqual(
            normalized.bounds,
            try PrivacyNormalizedRectV1(x: 100_000, y: 200_000, width: 250_000, height: 200_000)
        )
        let pixelSource = try PrivacyIntegerRectV1(x: 100, y: 200, width: 500, height: 200)
        let pixelUp = try coordinateRegion(
            id: C20PrivacyTransformTestSupport.id(61), space: .pixelImage,
            orientation: .up, sourceBounds: pixelSource,
            pixelWidth: 2_000, pixelHeight: 1_000
        )
        XCTAssertEqual(
            pixelUp.bounds,
            try PrivacyNormalizedRectV1(x: 50_000, y: 200_000, width: 250_000, height: 200_000)
        )
        XCTAssertEqual(
            try PrivacyCoordinateProjectionV1.normalized(
                sourceBounds: pixelSource, space: .pixelImage, orientation: .up,
                pixelWidth: 2_000, pixelHeight: 1_000, scale: .identity
            ),
            pixelUp.bounds
        )
        let pixelRight = try coordinateRegion(
            id: C20PrivacyTransformTestSupport.id(62), space: .pixelImage,
            orientation: .right, sourceBounds: pixelSource,
            pixelWidth: 2_000, pixelHeight: 1_000
        )
        XCTAssertEqual(
            pixelRight.bounds,
            try PrivacyNormalizedRectV1(x: 600_000, y: 50_000, width: 200_000, height: 250_000)
        )
        for (index, orientation) in PrivacyImageOrientationV1.allCases.enumerated() {
            let oriented = try coordinateRegion(
                id: C20PrivacyTransformTestSupport.id(70 + index), space: .pixelImage,
                orientation: orientation, sourceBounds: pixelSource,
                pixelWidth: 2_000, pixelHeight: 1_000
            )
            try oriented.validate()
            XCTAssertEqual(oriented.orientation, orientation)
        }
        let reducedScale = try PrivacyCoordinateScaleV1(numerator: 3, denominator: 2)
        let scaledPixel = try coordinateRegion(
            id: C20PrivacyTransformTestSupport.id(63), space: .pixelImage,
            orientation: .up, sourceBounds: pixelSource,
            pixelWidth: 2_000, pixelHeight: 1_000, coordinateScale: reducedScale
        )
        XCTAssertEqual(scaledPixel.coordinateScale, reducedScale)
        XCTAssertEqual(
            scaledPixel.bounds,
            try PrivacyNormalizedRectV1(x: 75_000, y: 300_000, width: 375_000, height: 300_000)
        )
        XCTAssertNotEqual(scaledPixel.regionSHA256, pixelUp.regionSHA256)
        XCTAssertNil(PrivacyCoordinateSpaceV1(rawValue: "UNKNOWN_SPACE"))
        XCTAssertNil(PrivacyImageOrientationV1(rawValue: "SIDEWAYS"))
        XCTAssertThrowsError(try PrivacyCoordinateScaleV1(numerator: 2, denominator: 4))
        XCTAssertThrowsError(try PrivacyCoordinateScaleV1(numerator: 0, denominator: 1))
        XCTAssertThrowsError(try PrivacyIntegerRectV1(x: -1, y: 0, width: 1, height: 1))
        XCTAssertThrowsError(try coordinateRegion(
            id: C20PrivacyTransformTestSupport.id(64), space: .normalizedImage,
            orientation: .up, sourceBounds: pixelSource,
            pixelWidth: 2_000, pixelHeight: 1_000
        ))
        let outOfBounds = try PrivacyIntegerRectV1(x: 1_900, y: 900, width: 200, height: 200)
        XCTAssertThrowsError(try coordinateRegion(
            id: C20PrivacyTransformTestSupport.id(65), space: .pixelImage,
            orientation: .up, sourceBounds: outOfBounds,
            pixelWidth: 2_000, pixelHeight: 1_000
        ))
        XCTAssertThrowsError(try PrivacyRegionV1(
            regionID: C20PrivacyTransformTestSupport.id(66), workspaceID: fixture.workspace,
            sourceContentID: fixture.original.contentID, sourceRevision: 1,
            sourceSHA256: fixture.manifest.sourceSHA256,
            coordinateSpaceVersion: "UNKNOWN_SPACE", bounds: fixture.regions[0].bounds,
            transformKind: .blur, reason: .person, author: fixture.author, order: 0,
            authoredAt: fixture.capturedAt, mutationID: fixture.mutationID
        ))
        XCTAssertThrowsError(try PrivacyRegionV1(
            regionID: C20PrivacyTransformTestSupport.id(67), workspaceID: fixture.workspace,
            sourceContentID: fixture.original.contentID, sourceRevision: 1,
            sourceSHA256: fixture.manifest.sourceSHA256,
            coordinateSpaceVersion: "NORMALIZED_1E6_V1", bounds: fixture.regions[0].bounds,
            transformKind: .blur, reason: .person, author: fixture.author, order: 0,
            authoredAt: fixture.capturedAt, mutationID: fixture.mutationID
        ))
        let localePolicies = try [
            Locale(identifier: "en_US_POSIX"), Locale(identifier: "tr_TR")
        ].map { locale in
            let kinds = fixture.policy.allowedTransformKinds.sorted {
                $0.rawValue.compare($1.rawValue, options: [.literal], range: nil, locale: locale) == .orderedAscending
            }
            let reasons = fixture.policy.allowedReasons.sorted {
                $0.rawValue.compare($1.rawValue, options: [.literal], range: nil, locale: locale) == .orderedAscending
            }
            return try PrivacyTransformPolicyV1(
                policyID: fixture.policy.policyID, workspaceID: fixture.workspace,
                purpose: fixture.policy.purpose, audience: fixture.policy.audience,
                allowedTransformKinds: kinds, allowedReasons: reasons,
                maximumAgeSeconds: fixture.policy.maximumAgeSeconds,
                effectiveAt: fixture.policy.effectiveAt, mutationID: fixture.mutationID
            )
        }
        XCTAssertEqual(localePolicies[0].policySHA256, localePolicies[1].policySHA256)
        try fixture.manifest.validate(policy: fixture.policy)
        try PrivacyTransformLifecycleClosureV1(
            policy: fixture.policy, regions: fixture.regions,
            manifest: fixture.manifest, review: fixture.approvedReview
        ).validate()
        try fixture.original.validatePrivacyDerivative(fixture.derivative)
        try ContentProvenanceGraphV1.validate(
            references: [fixture.original, fixture.derivative],
            originals: [fixture.originalProvenance], derivatives: [fixture.provenance]
        )
        let encoded = try PrivacyTransformCanonicalCodecV1.encode(fixture.manifest)
        XCTAssertEqual(
            try PrivacyTransformCanonicalCodecV1.decode(PrivacyTransformManifestV1.self, from: encoded),
            fixture.manifest
        )
        let registered = try ContentContractRegistryV1.c20BoundaryContracts()
        XCTAssertTrue(registered.contains("PrivacyTransformPolicyV1"))
        XCTAssertTrue(registered.contains("PrivacyTransformPublicationAuthorityV1"))
    }

    func testV23P03C20A01ApprovedProjectionRequiresSanitizedDerivativeAndExactAudience() async throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        assertCorpus(try loadCorpus())
        let decision = try PrivacyProjectionV1.decide(
            manifest: fixture.manifest, review: fixture.approvedReview, policy: fixture.policy,
            requestedAudience: .customerReport, currentSourceRevision: 1,
            currentSourceSHA256: fixture.manifest.sourceSHA256, at: fixture.capturedAt
        )
        XCTAssertTrue(decision.isAllowed)
        XCTAssertEqual(decision.derivative, fixture.derivative)
        try fixture.bundle.validate()
        let closure = PrivacyTransformLifecycleClosureV1(
            policy: fixture.policy, regions: fixture.regions,
            manifest: fixture.manifest, review: fixture.approvedReview
        )
        try ContentIntegrityV1.verifyPrivacyDerivative(
            closure: closure, locator: fixture.locator, observed: fixture.derivativeObserved
        )
        let publicationReceipt = try PrivacyTransformPublicationReceiptV1(
            bundle: fixture.bundle,
            canonicalMutationReceiptSHA256: C20PrivacyTransformTestSupport.canonicalMutationReceiptSHA256
        )
        try publicationReceipt.validate(
            bundle: fixture.bundle,
            expectedCanonicalMutationReceiptSHA256:
                C20PrivacyTransformTestSupport.canonicalMutationReceiptSHA256
        )
        let canonicalMutationReceipt = try C20PrivacyTransformTestSupport
            .makeCanonicalMutationReceipt(for: fixture)
        let canonicalDigest = try canonicalMutationReceipt.canonicalSHA256()
        let exactReceipt = try PrivacyTransformPublicationReceiptV1(
            bundle: fixture.bundle,
            canonicalMutationReceiptSHA256: canonicalDigest
        )
        try exactReceipt.validate(
            bundle: fixture.bundle,
            canonicalMutationReceipt: canonicalMutationReceipt
        )
        let shapeValidWrongReceipt = try PrivacyTransformPublicationReceiptV1(
            bundle: fixture.bundle,
            canonicalMutationReceiptSHA256: C20PrivacyTransformTestSupport.digest("c")
        )
        XCTAssertThrowsError(try shapeValidWrongReceipt.validate(
            bundle: fixture.bundle,
            expectedCanonicalMutationReceiptSHA256: canonicalDigest
        ))
        XCTAssertThrowsError(try shapeValidWrongReceipt.validate(
            bundle: fixture.bundle,
            canonicalMutationReceipt: canonicalMutationReceipt
        ))
        XCTAssertEqual(fixture.provenance.transform.kind, "PRIVACY")
        XCTAssertEqual(fixture.manifest.metadataSanitation.result, .complete)

        let authority = C20PrivacyPublicationAuthorityForAnchors()
        let coordinator = PrivacyTransformCoordinatorV1(authority: authority)
        let first = try await coordinator.publish(fixture.bundle)
        let second = try await coordinator.publish(fixture.bundle)
        let recovered = try await coordinator.recover(fixture.bundle)
        let recordedReview = try await coordinator.recordReview(
            fixture.approvedReview, manifest: fixture.manifest, policy: fixture.policy
        )
        let repeatedReview = try await coordinator.recordReview(
            fixture.approvedReview, manifest: fixture.manifest, policy: fixture.policy
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(recovered, first)
        XCTAssertEqual(recordedReview, fixture.approvedReview)
        XCTAssertEqual(repeatedReview, recordedReview)
        let publicationCount = await authority.publishCount
        let reviewCount = await authority.reviewCount
        XCTAssertEqual(publicationCount, 1)
        XCTAssertEqual(reviewCount, 1)
    }

    func testV23P03C20H01MissingRejectedStaleWrongPolicyAndDigestInputsFailClosed() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        assertCorpus(try loadCorpus())
        let deniedCases: [(PrivacyProjectionDenialV1, PrivacyTransformManifestV1?, PrivacyReviewReceiptV1?, PrivacyTransformPolicyV1, EvidenceAudienceV1, UInt64, String)] = [
            (.missingReview, fixture.manifest, nil, fixture.policy, .customerReport, 1, fixture.manifest.sourceSHA256),
            (.rejected, fixture.manifest, fixture.rejectedReview, fixture.policy, .customerReport, 1, fixture.manifest.sourceSHA256),
            (.stale, try C20PrivacyTransformTestSupport.manifest(from: fixture, staleState: .sourceChanged), fixture.approvedReview, fixture.policy, .customerReport, 1, fixture.manifest.sourceSHA256),
            (.wrongAudience, fixture.manifest, fixture.approvedReview, fixture.policy, .externalCollaborator, 1, fixture.manifest.sourceSHA256),
            (.sourceChanged, fixture.manifest, fixture.approvedReview, fixture.policy, .customerReport, 2, fixture.manifest.sourceSHA256),
        ]
        for (expected, manifest, review, policy, audience, revision, sourceSHA256) in deniedCases {
            let decision = try PrivacyProjectionV1.decide(
                manifest: manifest, review: review, policy: policy,
                requestedAudience: audience, currentSourceRevision: revision,
                currentSourceSHA256: sourceSHA256, at: fixture.capturedAt
            )
            XCTAssertEqual(decision.denial, expected)
            XCTAssertFalse(decision.isAllowed)
        }
        let otherPolicy = try PrivacyTransformPolicyV1(
            policyID: C20PrivacyTransformTestSupport.id(80), workspaceID: fixture.workspace,
            purpose: fixture.policy.purpose, audience: fixture.policy.audience,
            allowedTransformKinds: fixture.policy.allowedTransformKinds,
            allowedReasons: fixture.policy.allowedReasons, effectiveAt: fixture.capturedAt,
            mutationID: fixture.mutationID
        )
        let wrongPolicyDecision = try PrivacyProjectionV1.decide(
            manifest: fixture.manifest, review: fixture.approvedReview, policy: otherPolicy,
            requestedAudience: .customerReport, currentSourceRevision: 1,
            currentSourceSHA256: fixture.manifest.sourceSHA256, at: fixture.capturedAt
        )
        XCTAssertEqual(wrongPolicyDecision.denial, .wrongPolicy)
        let forgedReview = try C20PrivacyTransformTestSupport.forgedReview(
            fixture.approvedReview, receiptSHA256: C20PrivacyTransformTestSupport.digest("f")
        )
        let forgedDecision = try PrivacyProjectionV1.decide(
            manifest: fixture.manifest, review: forgedReview, policy: fixture.policy,
            requestedAudience: .customerReport, currentSourceRevision: 1,
            currentSourceSHA256: fixture.manifest.sourceSHA256, at: fixture.capturedAt
        )
        XCTAssertEqual(forgedDecision.denial, .digestMismatch)
        XCTAssertThrowsError(try PrivacyMetadataSanitationEvidenceV1(
            sanitizerID: "c20-sanitizer", sanitizerVersion: "1", result: .failed
        ))
        XCTAssertThrowsError(try PrivacyNormalizedRectV1(
            x: 999_999, y: 0, width: 2, height: 1
        ))
        XCTAssertThrowsError(try PrivacyTransformManifestV1(
            manifestID: fixture.manifest.manifestID, workspaceID: fixture.workspace,
            original: fixture.original, sourceRevision: 1, sourceSHA256: fixture.manifest.sourceSHA256,
            derivative: fixture.derivative, derivativeSHA256: fixture.manifest.derivativeSHA256,
            policy: fixture.policy, orderedRegions: [fixture.regions[0], fixture.regions[0]],
            rendererID: fixture.manifest.rendererID, rendererVersion: fixture.manifest.rendererVersion,
            metadataSanitation: fixture.manifest.metadataSanitation,
            renderedAt: fixture.capturedAt, mutationID: fixture.mutationID
        ))
        let mismatchedClosure = PrivacyTransformLifecycleClosureV1(
            policy: fixture.policy, regions: Array(fixture.regions.dropLast()),
            manifest: fixture.manifest, review: fixture.approvedReview
        )
        XCTAssertThrowsError(try mismatchedClosure.validate())
        XCTAssertThrowsError(try fixture.original.validatePrivacyDerivative(fixture.original))
    }

    func testV23P03C20I01PublicationRowsAndRecoveryAreAtomicAndIdempotent() async throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        assertCorpus(try loadCorpus())
        XCTAssertEqual(try fixture.policyRow.value(), fixture.policy)
        XCTAssertEqual(try fixture.regionRows.map { try $0.value() }, fixture.regions)
        XCTAssertThrowsError(try fixture.manifestRow.value())
        XCTAssertThrowsError(try fixture.reviewRow.value())
        XCTAssertEqual(try fixture.manifestRow.value(policy: fixture.policy), fixture.manifest)
        XCTAssertEqual(
            try fixture.reviewRow.value(manifest: fixture.manifest, policy: fixture.policy),
            fixture.approvedReview
        )
        let authority = C20PrivacyPublicationAuthorityForAnchors()
        let lifecycle = PrivacyTransformLifecycleAdapterV1(authority: authority)
        let first = try await lifecycle.resume(bundle: fixture.bundle)
        let retry = try await lifecycle.resume(bundle: fixture.bundle)
        XCTAssertEqual(first, retry)
        let publicationCount = await authority.publishCount
        XCTAssertEqual(publicationCount, 1)
        XCTAssertEqual(lifecycle.disposition(hasDerivativeBytes: false, hasManifest: false, hasReview: false, receiptValid: false), .retain)
        XCTAssertEqual(lifecycle.disposition(hasDerivativeBytes: true, hasManifest: false, hasReview: false, receiptValid: false), .deleteRegenerableDerivative)
        XCTAssertEqual(lifecycle.disposition(hasDerivativeBytes: true, hasManifest: true, hasReview: false, receiptValid: false), .quarantinePartialEffect)
        XCTAssertEqual(lifecycle.disposition(hasDerivativeBytes: true, hasManifest: true, hasReview: true, receiptValid: true), .retain)

        var localStore = try LocalContentStoreV1(workspaceID: fixture.original.workspaceID)
        let originalDigest = try XCTUnwrap(fixture.originalObserved.digests.digest(for: .sha256))
        let originalLocator = try ContentLocatorV1(
            locatorID: "c20-original-locator", workspaceID: fixture.original.workspaceID,
            contentID: fixture.original.contentID, locatorRevision: 1,
            contentDigest: originalDigest, expectedByteLength: fixture.original.byteLength
        )
        try localStore.store(
            reference: fixture.original, locator: originalLocator,
            observed: fixture.originalObserved,
            availability: .available(remainingByteCapacity: 1_000_000)
        )
        try localStore.storePrivacyDerivative(
            closure: PrivacyTransformLifecycleClosureV1(
                policy: fixture.policy, regions: fixture.regions,
                manifest: fixture.manifest, review: fixture.approvedReview
            ), locator: fixture.locator, observed: fixture.derivativeObserved,
            availability: .available(remainingByteCapacity: 1_000_000)
        )
        XCTAssertEqual(localStore.immutableOriginals(), [fixture.original])
        try localStore.deleteRegenerableDerivative(
            contentID: fixture.derivative.contentID, provenance: fixture.provenance
        )
        XCTAssertEqual(localStore.immutableOriginals(), [fixture.original])
    }

    func testV23P03C20R01V19BackupRestoreDeleteEraseAndProjectionConsumersRemainDeniedByDefault() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        assertCorpus(try loadCorpus())
        XCTAssertEqual(PersistentSchemaV19.versionIdentifier, Schema.Version(19, 0, 0))
        XCTAssertEqual(PersistentSchemaV19.models.count, 77)
        XCTAssertEqual(PersistentSchemaMigrationPlanV18.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV18.stages.count, 1)
        try V19PrivacyTransformImportBoundaryV1.validate(persistent: 19, records: 18)
        XCTAssertThrowsError(try V19PrivacyTransformImportBoundaryV1.validate(persistent: 18, records: 18))
        XCTAssertEqual(V19BackupPrivacyTransformRecordV1.Kind.allCases.count, 4)
        XCTAssertEqual(Set(fixture.backupRecords.map { "\($0.kind.rawValue)|\($0.id.uuidString)" }).count, 4)
        for record in fixture.backupRecords {
            XCTAssertEqual(record.workspaceID, fixture.workspace.rawValue)
            XCTAssertFalse(record.canonicalData.isEmpty)
            switch record.kind {
            case .policy:
                XCTAssertEqual(try PrivacyTransformCanonicalCodecV1.decode(PrivacyTransformPolicyV1.self, from: record.canonicalData), fixture.policy)
            case .region:
                XCTAssertEqual(try PrivacyTransformCanonicalCodecV1.decode(PrivacyRegionV1.self, from: record.canonicalData), fixture.regions[0])
            case .manifest:
                XCTAssertEqual(try PrivacyTransformCanonicalCodecV1.decode(PrivacyTransformManifestV1.self, from: record.canonicalData), fixture.manifest)
            case .reviewReceipt:
                XCTAssertEqual(try PrivacyTransformCanonicalCodecV1.decode(PrivacyReviewReceiptV1.self, from: record.canonicalData), fixture.approvedReview)
            }
        }
        let projectionConsumers = ["REPORT", "OPEN_JSON", "LOCAL_SEARCH", "SHARE", "BACKUP", "RESTORE", "DELETE", "ERASE", "REPLAY"]
        for consumer in projectionConsumers {
            let decision = try PrivacyProjectionV1.decide(
                manifest: fixture.manifest, review: fixture.approvedReview, policy: fixture.policy,
                requestedAudience: .externalCollaborator, currentSourceRevision: 1,
                currentSourceSHA256: fixture.manifest.sourceSHA256, at: fixture.capturedAt
            )
            XCTAssertFalse(decision.isAllowed, "\(consumer) must not bypass privacy projection")
            XCTAssertEqual(decision.denial, .wrongAudience)
        }
        XCTAssertTrue(fixture.original.byteRole == .immutableOriginal)
        XCTAssertNotEqual(fixture.original.contentID, fixture.derivative.contentID)
        XCTAssertNotEqual(fixture.originalObserved.digests, fixture.derivativeObserved.digests)
    }
}

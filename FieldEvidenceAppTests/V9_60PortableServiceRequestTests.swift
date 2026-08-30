import CryptoKit
import Foundation
import XCTest

@testable import FieldEvidenceApp

enum C52ServiceRequestBoundaryTokenV1 {
    static let cardID = "V23-P03-C52"
    static let proofDomain = PortableServiceRequestProtocolReleaseV1.proofDomain
    static let evidenceIDs = [
        "V23-P03-C52-G01",
        "V23-P03-C52-A01",
        "V23-P03-C52-H01",
        "V23-P03-C52-I01",
        "V23-P03-C52-R01"
    ]
}

private struct C52ProtocolFixture: Decodable {
    let protocolID: String
    let protocolVersion: Int
    let invitationSchemaID: String
    let submissionSchemaID: String
    let invitationFileExtension: String
    let submissionFileExtension: String
    let proofDomain: String
    let cleartextReadableAndForwardable: Bool
    let envelopeInnerKindPermitted: Bool
    let allowedMediaFormats: [String]
    let capabilityByteCount: Int
    let proofByteCount: Int
    let forwardingTransfersSubmissionAbility: Bool
    let sharingProvesDelivery: Bool
}

private struct C52ProofVectorFixture: Decodable {
    let vectorID: String
    let capabilityHex: String
    let protocolReleaseDigestHex: String
    let invitationPublicID: String
    let invitationManifestDigestHex: String
    let frozenScopeSnapshotDigestHex: String
    let submissionPublicID: String
    let canonicalSubmissionBodyDigestHex: String
    let mediaManifestDigestHex: String
    let transcriptByteCount: Int
    let transcriptSHA256: String
    let proofHMACSHA256: String
}

private struct C52DuplicateFixture: Decodable {
    let caseID: String
    let scope: String
    let sharedAsset: Bool
    let reason: String
    let suggestionOnly: Bool
}

private struct C52TriageFixture: Decodable {
    let disposition: String
    let state: String
    let canonicalWrite: Bool
}

private struct C52RetryFixture: Decodable {
    let sameSubmissionIDAndDigestReturnsSameReceipt: Bool
    let sameSubmissionIDDifferentBytesQuarantines: Bool
    let effectBeforeReceiptConverges: Bool
    let canonicalRequestLinkCountIsZeroOrOne: Bool
    let siblingsArePreserved: Bool
}

private struct C52LifecycleFixture: Decodable {
    let serviceNamespaceIndependentFromReview: Bool
    let v1ToV2PreservesBytesIDsTimestampsAndState: Bool
    let backupPreservesCanonicalHistory: Bool
    let cloneAndForkPreserveHistory: Bool
    let cloneAndForkInvalidateOutstandingCapabilities: Bool
    let eraseRemovesAppOwnedProtectedState: Bool
    let escapedCopiesCanBeAcknowledgedButNotRecalled: Bool
}

private struct C52PrivacyFixture: Decodable {
    let requesterIdentityVerified: Bool
    let contactVerified: Bool
    let urgencyVerified: Bool
    let capabilityInSubmission: Bool
    let capabilityInReportsLogsSearchAccessibility: Bool
    let recipientMediaIsDerivedOnly: Bool
    let contactPromotionIsOperationalOnly: Bool
}

private struct C52StatusFixture: Decodable {
    let customerSafeBoundedArtifact: Bool
    let deliveryClaimed: Bool
    let emergencyHandlingClaimed: Bool
    let slaClaimed: Bool
}

private struct C52WorkConversionFixture: Decodable {
    let requiresExplicitChoice: Bool
    let bindsRequestRevision: Bool
    let bindsTargetRevision: Bool
    let usesMutationID: Bool
    let exactlyOneCanonicalLink: Bool
    let unlinkIsAppendOnlyReversal: Bool
    let automaticWorkCreation: Bool
}

private struct C52LocalizationFixture: Decodable {
    let sourceLocale: String
    let englishOnly: Bool
    let deliveryWordsForbidden: Bool
    let emergencyWordsForbidden: Bool
    let slaWordsForbidden: Bool
}

private struct C52PortableServiceRequestCorpusFixture: Decodable {
    let schema: String
    let schemaVersion: Int
    let cardID: String
    let corpusID: String
    let testOnly: Bool
    let synthetic: Bool
    let immutable: Bool
    let containsCustomerData: Bool
    let containsSecrets: Bool
    let contracts: [String]
    let evidenceIDs: [String]
    let protocolFixture: C52ProtocolFixture
    let proofVector: C52ProofVectorFixture
    let channels: [String]
    let dispositions: [String]
    let states: [String]
    let duplicateCases: [C52DuplicateFixture]
    let triageCases: [C52TriageFixture]
    let hostileCases: [String]
    let interruptionBoundaries: [String]
    let retryRules: C52RetryFixture
    let lifecycle: C52LifecycleFixture
    let privacy: C52PrivacyFixture
    let status: C52StatusFixture
    let workConversion: C52WorkConversionFixture
    let localization: C52LocalizationFixture
    let typedAnchor: String

    private enum CodingKeys: String, CodingKey {
        case schema, schemaVersion, cardID, corpusID, testOnly, synthetic, immutable
        case containsCustomerData, containsSecrets, contracts, evidenceIDs
        case protocolFixture = "protocol"
        case proofVector, channels, dispositions, states, duplicateCases, triageCases
        case hostileCases, interruptionBoundaries, retryRules, lifecycle, privacy, status
        case workConversion, localization, typedAnchor
    }
}

private struct C52GoldenServiceRequest {
    let release: PortableServiceRequestProtocolReleaseV1
    let scope: ServiceRequestScopeSnapshotV1
    let body: ServiceRequestSubmissionBodyV1
    let media: ServiceRequestMediaManifestV1
    let manifest: ServiceRequestInvitationManifestV1
    let invitation: PortableServiceRequestInvitationV1
    let capability: ServiceRequestSubmissionCapabilityV1
    let submission: PortableServiceRequestSubmissionV1
    let sourceBytes: Data
}

private enum C52PortableServiceRequestTestSupport {
    static let workspace = WorkspaceID(rawValue: UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5301")!)
    static let siteID = UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5302")!
    static let assetID = UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5303")!
    static let invitationID = try! ServiceRequestInvitationPublicIDV1("INV-C52-GOLDEN-001")
    static let submissionID = try! ServiceRequestSubmissionPublicIDV1("SUB-C52-GOLDEN-001")

    static func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    static func digest(_ character: Character) -> String {
        String(repeating: String(character), count: ServiceRequestLimitsV1.digestByteCount * 2)
    }

    static func data(hex: String) throws -> Data {
        guard hex.count.isMultiple(of: 2) else { throw ServiceRequestFailureV1.invalidDigest }
        var result = Data()
        result.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                throw ServiceRequestFailureV1.invalidDigest
            }
            result.append(byte)
            index = next
        }
        return result
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func fixture() throws -> C52PortableServiceRequestCorpusFixture {
        let bundle = Bundle(for: V9_60PortableServiceRequestTests.self)
        let url = bundle.url(
            forResource: "V22P03C52PortableServiceRequestCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V22/ServiceRequests"
        ) ?? bundle.url(
            forResource: "V22P03C52PortableServiceRequestCorpusV1",
            withExtension: "json"
        )
        guard let url else { throw ServiceRequestFailureV1.invalidValue }
        return try JSONDecoder().decode(
            C52PortableServiceRequestCorpusFixture.self,
            from: Data(contentsOf: url)
        )
    }

    static func golden() throws -> C52GoldenServiceRequest {
        let budget = try ServiceRequestExchangeBudgetV1(
            maximumScopedAssets: 2,
            maximumMediaItems: 2,
            maximumSingleMediaBytes: 1_024,
            maximumTotalMediaBytes: 2_048,
            maximumSubmissionBytes: 8_192,
            maximumDuplicateCandidates: 4
        )
        let release = try PortableServiceRequestProtocolReleaseV1(budget: budget)
        let asset = try ServiceRequestAssetScopeSnapshotV1(
            assetID: assetID,
            expectedRevision: 3,
            semanticSHA256: digest("a")
        )
        let scope = try ServiceRequestScopeSnapshotV1(
            siteID: siteID,
            siteExpectedRevision: 5,
            siteSemanticSHA256: digest("b"),
            assets: [asset]
        )
        let manifest = try ServiceRequestInvitationManifestV1(
            protocolRelease: release,
            invitationPublicID: invitationID,
            scope: scope
        )
        let capability = try ServiceRequestSubmissionCapabilityV1(
            rawBytes: data(hex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
        )
        let invitation = try PortableServiceRequestInvitationV1(
            manifest: manifest,
            capability: capability
        )
        let requester = try ServiceRequestRequesterAssertionV1(
            displayName: "Requester",
            organization: "Example organization"
        )
        let contact = try ServiceRequestContactAssertionV1(
            value: "+1 555 0100",
            wording: "SELF_ASSERTED_UNVERIFIED"
        )
        let body = try ServiceRequestSubmissionBodyV1(
            requestText: "Door closer needs adjustment",
            statedDate: Date(timeIntervalSince1970: 1_700_000_000),
            urgency: .urgentSelfAsserted,
            requester: requester,
            contact: contact,
            category: "hardware"
        )
        let mediaEntry = try ServiceRequestMediaEntryV1(
            mediaID: "media-001",
            format: .jpeg,
            byteCount: 16,
            pixelWidth: 640,
            pixelHeight: 480,
            sha256: digest("c")
        )
        let media = try ServiceRequestMediaManifestV1(entries: [mediaEntry])
        let input = try ServiceRequestCapabilityProofInputV1(
            protocolReleaseDigest: data(hex: release.releaseSHA256),
            invitationPublicID: invitationID,
            invitationManifestDigest: data(hex: manifest.manifestSHA256),
            frozenScopeSnapshotDigest: data(hex: scope.scopeSHA256),
            submissionPublicID: submissionID,
            canonicalSubmissionBodyDigest: data(hex: try ServiceRequestCanonicalCodecV1.sha256(body)),
            mediaManifestDigest: data(hex: media.manifestSHA256)
        )
        let proof = try ServiceRequestCapabilityProofCodecV1.makeProof(
            capability: capability,
            input: input
        )
        let submission = try PortableServiceRequestSubmissionV1(
            protocolReleaseSHA256: release.releaseSHA256,
            invitationManifest: manifest,
            submissionPublicID: submissionID,
            body: body,
            mediaManifest: media,
            proof: proof
        )
        return C52GoldenServiceRequest(
            release: release,
            scope: scope,
            body: body,
            media: media,
            manifest: manifest,
            invitation: invitation,
            capability: capability,
            submission: submission,
            sourceBytes: try ServiceRequestCanonicalCodecV1.data(submission)
        )
    }

    static func requestReference() throws -> ServiceRequestRevisionReferenceV1 {
        try ServiceRequestRevisionReferenceV1(
            recordID: uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5310"),
            revision: 1,
            recordSHA256: digest("d")
        )
    }

    static func jsonAddingUnknownKey(_ data: Data, key: String) throws -> Data {
        try jsonReplacing(data, key: key, value: true)
    }

    static func jsonReplacing(_ data: Data, key: String, value: Any) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceRequestFailureV1.invalidValue
        }
        object[key] = value
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

@MainActor
final class V9_60PortableServiceRequestTests: XCTestCase {
    func testV23P03C52G01GoldenServiceRequestInvitationSubmissionAndCapabilityProofUseTypedContracts() throws {
        let corpus = try C52PortableServiceRequestTestSupport.fixture()
        let vector = corpus.proofVector
        let input = try ServiceRequestCapabilityProofInputV1(
            protocolReleaseDigest: try C52PortableServiceRequestTestSupport.data(hex: vector.protocolReleaseDigestHex),
            invitationPublicID: try ServiceRequestInvitationPublicIDV1(vector.invitationPublicID),
            invitationManifestDigest: try C52PortableServiceRequestTestSupport.data(hex: vector.invitationManifestDigestHex),
            frozenScopeSnapshotDigest: try C52PortableServiceRequestTestSupport.data(hex: vector.frozenScopeSnapshotDigestHex),
            submissionPublicID: try ServiceRequestSubmissionPublicIDV1(vector.submissionPublicID),
            canonicalSubmissionBodyDigest: try C52PortableServiceRequestTestSupport.data(hex: vector.canonicalSubmissionBodyDigestHex),
            mediaManifestDigest: try C52PortableServiceRequestTestSupport.data(hex: vector.mediaManifestDigestHex)
        )
        let capability = try ServiceRequestSubmissionCapabilityV1(
            rawBytes: C52PortableServiceRequestTestSupport.data(hex: vector.capabilityHex)
        )
        let transcript = try ServiceRequestCapabilityProofCodecV1.transcript(for: input)
        let proof = try ServiceRequestCapabilityProofCodecV1.makeProof(
            capability: capability,
            input: input
        )
        XCTAssertEqual(vector.vectorID, "SRV1-001")
        XCTAssertEqual(transcript.count, vector.transcriptByteCount)
        XCTAssertTrue(transcript.starts(with: Data(PortableServiceRequestProtocolReleaseV1.proofDomain.utf8)))
        XCTAssertEqual(ServiceRequestCanonicalCodecV1.sha256(transcript), vector.transcriptSHA256)
        XCTAssertEqual(C52PortableServiceRequestTestSupport.hex(proof.rawBytes), vector.proofHMACSHA256)
        XCTAssertTrue(try ServiceRequestCapabilityProofCodecV1.verify(proof, capability: capability, input: input))

        let golden = try C52PortableServiceRequestTestSupport.golden()
        let release = golden.release
        let protocolFixture = corpus.protocolFixture
        XCTAssertEqual(release.protocolID, protocolFixture.protocolID)
        XCTAssertEqual(release.protocolVersion, protocolFixture.protocolVersion)
        XCTAssertEqual(release.invitationSchemaID, protocolFixture.invitationSchemaID)
        XCTAssertEqual(release.submissionSchemaID, protocolFixture.submissionSchemaID)
        XCTAssertEqual(release.invitationFileExtension, protocolFixture.invitationFileExtension)
        XCTAssertEqual(release.submissionFileExtension, protocolFixture.submissionFileExtension)
        XCTAssertEqual(release.proofDomain, protocolFixture.proofDomain)
        XCTAssertEqual(release.cleartextReadableAndForwardable, protocolFixture.cleartextReadableAndForwardable)
        XCTAssertEqual(release.envelopeInnerKindPermitted, protocolFixture.envelopeInnerKindPermitted)
        XCTAssertEqual(release.allowedMediaFormats.map(\.rawValue), protocolFixture.allowedMediaFormats)
        XCTAssertEqual(golden.capability.rawBytes.count, protocolFixture.capabilityByteCount)
        XCTAssertEqual(golden.submission.proof.rawBytes.count, protocolFixture.proofByteCount)
        XCTAssertTrue(protocolFixture.forwardingTransfersSubmissionAbility)
        XCTAssertFalse(protocolFixture.sharingProvesDelivery)
        try golden.release.validate()
        try golden.invitation.validate()
        try golden.submission.validate()
        XCTAssertEqual(golden.invitation.submissionCapabilityBytes, golden.capability.rawBytes)
        XCTAssertFalse(golden.sourceBytes.containsSubsequence(golden.capability.rawBytes))
        XCTAssertTrue(PortableServiceRequestFormatBoundaryV1.invitationIsCleartext)
        XCTAssertTrue(PortableServiceRequestFormatBoundaryV1.submissionIsCleartext)
        XCTAssertFalse(PortableServiceRequestFormatBoundaryV1.serviceRequestEnvelopeInnerKindPermitted)
    }

    func testV23P03C52A01ManualAndPortableRequestsRequireExplicitDispositionAndExplainableDuplicateCandidates() throws {
        let corpus = try C52PortableServiceRequestTestSupport.fixture()
        XCTAssertEqual(Set(ServiceRequestSourceKindV1.allCases.map(\.rawValue)), Set(corpus.channels))
        XCTAssertEqual(ServiceRequestSourceKindV1.allCases.count, corpus.channels.count)
        XCTAssertEqual(ServiceRequestImportDispositionV1.allCases.map(\.rawValue), corpus.dispositions)
        XCTAssertEqual(ServiceRequestStateV1.allCases.map(\.rawValue), corpus.states)
        XCTAssertEqual(
            corpus.triageCases.map(\.canonicalWrite),
            ServiceRequestImportDispositionV1.allCases.map(ServiceRequestImportPreviewV1.writesCanonical)
        )

        let golden = try C52PortableServiceRequestTestSupport.golden()
        XCTAssertEqual(golden.body.contact.wording, "SELF_ASSERTED_UNVERIFIED")
        XCTAssertEqual(golden.body.urgency, .urgentSelfAsserted)
        XCTAssertFalse(PortableServiceRequestFormatBoundaryV1.requesterIdentityIsVerified)
        XCTAssertFalse(PortableServiceRequestFormatBoundaryV1.urgencyIsVerified)

        let prior = try C52PortableServiceRequestTestSupport.requestReference()
        let reason = try ServiceRequestDuplicateReasonV1(
            kind: .exactCategory,
            explanation: "Same Site and Asset have the same explicit category"
        )
        let candidate = try ServiceRequestDuplicateCandidateV1(
            record: prior,
            sharedSiteID: golden.scope.siteID,
            sharedAssetID: golden.scope.assets.first?.assetID,
            reasons: [reason]
        )
        let projection = try ServiceRequestDuplicateProjectionV1(
            basisRequestSHA256: C52PortableServiceRequestTestSupport.digest("e"),
            ruleReleaseSHA256: C52PortableServiceRequestTestSupport.digest("f"),
            candidates: [candidate]
        )
        XCTAssertTrue(projection.suggestionOnly)
        XCTAssertEqual(
            projection.candidates.first?.reasons.first?.kind,
            .some(ServiceRequestDuplicateReasonKindV1.exactCategory)
        )
        XCTAssertTrue(corpus.duplicateCases.allSatisfy(\.suggestionOnly))
        XCTAssertEqual(corpus.duplicateCases.filter { $0.scope == "CROSS_SITE" }.count, 1)
        XCTAssertTrue(corpus.retryRules.siblingsArePreserved)
        XCTAssertTrue(C52ServiceRequestCoordinatorBoundaryV1.dispositionIsExplicit)
        XCTAssertTrue(C52ServiceRequestCoordinatorBoundaryV1.duplicateCandidatesAreSuggestionOnly)

        for (index, source) in ServiceRequestSourceKindV1.allCases.enumerated() where source != .portableSubmission {
            let record = try ServiceRequestRecordV1(
                recordID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A53\(String(format: "%02d", index))"),
                workspaceID: C52PortableServiceRequestTestSupport.workspace,
                source: source,
                scope: golden.scope,
                body: golden.body,
                mediaManifest: golden.media,
                acceptedSourceBytes: try CanonicalServiceRequestSourceBytesV1(Data("manual-\(source.rawValue)".utf8)),
                capabilityAssessment: ServiceRequestCapabilityAssessmentV1(
                    proofValidity: .unavailable,
                    importEligibility: .unavailable
                ),
                revision: 1,
                mutationID: try MutationIDV1(rawValue: UUID()),
                recordedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
            try record.validate()
            XCTAssertEqual(record.source, source)
        }
    }

    func testV23P03C52H01TamperReplayDivergenceScopeAndUnverifiedIdentityInputsFailClosed() throws {
        let corpus = try C52PortableServiceRequestTestSupport.fixture()
        let golden = try C52PortableServiceRequestTestSupport.golden()
        var tamperedSource = golden.sourceBytes
        tamperedSource.append(0x20)
        XCTAssertThrowsError(try ServiceRequestCanonicalCodecV1.decode(
            PortableServiceRequestSubmissionV1.self,
            from: tamperedSource
        ))

        let vector = corpus.proofVector
        let input = try ServiceRequestCapabilityProofInputV1(
            protocolReleaseDigest: try C52PortableServiceRequestTestSupport.data(hex: vector.protocolReleaseDigestHex),
            invitationPublicID: try ServiceRequestInvitationPublicIDV1(vector.invitationPublicID),
            invitationManifestDigest: try C52PortableServiceRequestTestSupport.data(hex: vector.invitationManifestDigestHex),
            frozenScopeSnapshotDigest: try C52PortableServiceRequestTestSupport.data(hex: vector.frozenScopeSnapshotDigestHex),
            submissionPublicID: try ServiceRequestSubmissionPublicIDV1(vector.submissionPublicID),
            canonicalSubmissionBodyDigest: try C52PortableServiceRequestTestSupport.data(hex: vector.canonicalSubmissionBodyDigestHex),
            mediaManifestDigest: try C52PortableServiceRequestTestSupport.data(hex: vector.mediaManifestDigestHex)
        )
        let capability = try ServiceRequestSubmissionCapabilityV1(
            rawBytes: C52PortableServiceRequestTestSupport.data(hex: vector.capabilityHex)
        )
        let proof = try ServiceRequestCapabilityProofCodecV1.makeProof(capability: capability, input: input)
        let wrongCapability = try ServiceRequestSubmissionCapabilityV1(
            rawBytes: Data(repeating: 0xff, count: ServiceRequestLimitsV1.capabilityByteCount)
        )
        XCTAssertFalse(try ServiceRequestCapabilityProofCodecV1.verify(proof, capability: wrongCapability, input: input))
        let wrongSubmission = try ServiceRequestCapabilityProofInputV1(
            protocolReleaseDigest: input.protocolReleaseDigest,
            invitationPublicID: input.invitationPublicID,
            invitationManifestDigest: input.invitationManifestDigest,
            frozenScopeSnapshotDigest: input.frozenScopeSnapshotDigest,
            submissionPublicID: try ServiceRequestSubmissionPublicIDV1("SUB-C52-DIVERGENT-001"),
            canonicalSubmissionBodyDigest: input.canonicalSubmissionBodyDigest,
            mediaManifestDigest: input.mediaManifestDigest
        )
        XCTAssertFalse(try ServiceRequestCapabilityProofCodecV1.verify(proof, capability: capability, input: wrongSubmission))
        XCTAssertThrowsError(try ServiceRequestSubmissionCapabilityV1(rawBytes: Data(repeating: 0, count: 31)))
        XCTAssertThrowsError(try ServiceRequestInvitationPublicIDV1("INV-C52-\u{00E9}"))
        XCTAssertThrowsError(try ServiceRequestSubmissionBodyV1(
            requestText: "bad\u{0000}text",
            urgency: .routine,
            requester: ServiceRequestRequesterAssertionV1(),
            contact: ServiceRequestContactAssertionV1(value: nil)
        ))
        XCTAssertThrowsError(try ServiceRequestMediaEntryV1(
            mediaID: "too-large",
            format: .jpeg,
            byteCount: ServiceRequestLimitsV1.maximumSingleMediaBytes + 1,
            pixelWidth: 1,
            pixelHeight: 1,
            sha256: C52PortableServiceRequestTestSupport.digest("a")
        ))
        XCTAssertThrowsError(try CanonicalServiceRequestSourceBytesV1(Data()))
        XCTAssertTrue(corpus.hostileCases.count >= 20)
        XCTAssertTrue(corpus.hostileCases.contains("TRAVERSAL"))
        XCTAssertTrue(corpus.hostileCases.contains("SYMLINK"))
        XCTAssertTrue(corpus.hostileCases.contains("EXIF_GPS_METADATA"))
        XCTAssertFalse(corpus.privacy.requesterIdentityVerified)
        XCTAssertFalse(corpus.privacy.contactVerified)
        XCTAssertFalse(corpus.privacy.urgencyVerified)
        XCTAssertFalse(corpus.privacy.capabilityInSubmission)
        XCTAssertFalse(corpus.status.deliveryClaimed)
        XCTAssertFalse(corpus.status.emergencyHandlingClaimed)
        XCTAssertFalse(corpus.status.slaClaimed)
    }

    func testV23P03C52I01ZeroWritePreviewAndEffectBeforeReceiptConversionRecoverExactlyOnce() throws {
        let corpus = try C52PortableServiceRequestTestSupport.fixture()
        XCTAssertFalse(C52ServiceRequestCoordinatorBoundaryV1.previewWritesWorkspace)
        XCTAssertTrue(C52ServiceRequestCoordinatorBoundaryV1.durableReceiptQueryPrecedesWrite)
        XCTAssertTrue(C52ServiceRequestCoordinatorBoundaryV1.effectBeforeReceiptRecoveryIsRequired)
        XCTAssertTrue(corpus.retryRules.sameSubmissionIDAndDigestReturnsSameReceipt)
        XCTAssertTrue(corpus.retryRules.sameSubmissionIDDifferentBytesQuarantines)
        XCTAssertTrue(corpus.retryRules.effectBeforeReceiptConverges)
        XCTAssertTrue(corpus.retryRules.canonicalRequestLinkCountIsZeroOrOne)
        XCTAssertEqual(corpus.interruptionBoundaries.count, 12)

        let request = try C52PortableServiceRequestTestSupport.requestReference()
        let workspace = C52PortableServiceRequestTestSupport.workspace
        let target = WorkSubjectReferenceV1(
            kind: .asset,
            subjectID: C52PortableServiceRequestTestSupport.assetID,
            revision: 3,
            ownerAssetID: nil
        )
        let mutationID = try MutationIDV1(
            rawValue: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5320")
        )
        let link = try ServiceRequestWorkLinkEventV1(
            eventID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5321"),
            workspaceID: workspace,
            request: request,
            target: target,
            choice: .activity(
                activityID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5322"),
                expectedRevision: 1,
                semanticSHA256: C52PortableServiceRequestTestSupport.digest("a")
            ),
            canonicalWorkID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5323"),
            canonicalWorkRevision: 1,
            canonicalWorkSHA256: C52PortableServiceRequestTestSupport.digest("b"),
            kind: .link,
            revision: 1,
            mutationID: mutationID,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        try link.validate()
        let identity = try WorkspaceEntityIdentityV1(
            kind: .serviceRequestWorkLinkEvent,
            id: link.eventID
        )
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: workspace,
            generationID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5330"),
            writerInstanceID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5331"),
            workspaceRevision: 0,
            entityRevisions: [WorkspaceEntityRevisionV1(identity: identity, revision: 0)]
        )
        let plan = try ServiceRequestWorkConversionPlanV1(
            workspaceID: workspace,
            expectedRevision: expected,
            event: link
        )
        try plan.validate()
        let receipt = try ServiceRequestWorkConversionReceiptV1(
            plan: plan,
            canonicalMutationReceiptSHA256: C52PortableServiceRequestTestSupport.digest("c")
        )
        try receipt.validate()
        XCTAssertEqual(receipt.event, link)
        XCTAssertEqual(receipt.mutationID, mutationID)

        let encodedPlan = try ServiceRequestCanonicalCodecV1.data(plan)
        XCTAssertEqual(
            try ServiceRequestCanonicalCodecV1.decode(
                ServiceRequestWorkConversionPlanV1.self,
                from: encodedPlan
            ),
            plan
        )
        XCTAssertThrowsError(
            try ServiceRequestCanonicalCodecV1.decode(
                ServiceRequestWorkConversionPlanV1.self,
                from: C52PortableServiceRequestTestSupport.jsonAddingUnknownKey(
                    encodedPlan,
                    key: "c52UnexpectedPlanKey"
                )
            )
        )
        XCTAssertThrowsError(
            try ServiceRequestCanonicalCodecV1.decode(
                ServiceRequestWorkConversionPlanV1.self,
                from: C52PortableServiceRequestTestSupport.jsonReplacing(
                    encodedPlan,
                    key: "zeroWrite",
                    value: false
                )
            )
        )

        let encodedReceipt = try ServiceRequestCanonicalCodecV1.data(receipt)
        XCTAssertEqual(
            try ServiceRequestCanonicalCodecV1.decode(
                ServiceRequestWorkConversionReceiptV1.self,
                from: encodedReceipt
            ),
            receipt
        )
        XCTAssertThrowsError(
            try ServiceRequestCanonicalCodecV1.decode(
                ServiceRequestWorkConversionReceiptV1.self,
                from: C52PortableServiceRequestTestSupport.jsonAddingUnknownKey(
                    encodedReceipt,
                    key: "c52UnexpectedReceiptKey"
                )
            )
        )
        XCTAssertThrowsError(
            try ServiceRequestCanonicalCodecV1.decode(
                ServiceRequestWorkConversionReceiptV1.self,
                from: C52PortableServiceRequestTestSupport.jsonReplacing(
                    encodedReceipt,
                    key: "receiptSHA256",
                    value: C52PortableServiceRequestTestSupport.digest("z")
                )
            )
        )

        let emptyStoreEnvelope = try PortableExchangeSessionEnvelopeV2(
            generationID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5350"),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_202)
        )
        let encodedStoreEnvelope = try StoreMigrationCanonicalJSONV1.encode(emptyStoreEnvelope)
        XCTAssertEqual(
            try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
                PortableExchangeSessionEnvelopeV2.self,
                from: encodedStoreEnvelope,
                validate: { value in _ = try value.validated() }
            ),
            emptyStoreEnvelope
        )
        XCTAssertThrowsError(
            try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
                PortableExchangeSessionEnvelopeV2.self,
                from: C52PortableServiceRequestTestSupport.jsonAddingUnknownKey(
                    encodedStoreEnvelope,
                    key: "c52UnexpectedStoreKey"
                ),
                validate: { value in _ = try value.validated() }
            )
        )
        XCTAssertThrowsError(
            try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
                PortableExchangeSessionEnvelopeV2.self,
                from: C52PortableServiceRequestTestSupport.jsonReplacing(
                    encodedStoreEnvelope,
                    key: "schemaVersion",
                    value: 99
                ),
                validate: { value in _ = try value.validated() }
            )
        )

        let reversalMutationID = try MutationIDV1(
            rawValue: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5324")
        )
        let reversal = try ServiceRequestWorkLinkEventV1(
            eventID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5325"),
            workspaceID: workspace,
            request: request,
            target: target,
            choice: link.choice,
            canonicalWorkID: link.canonicalWorkID,
            canonicalWorkRevision: link.canonicalWorkRevision,
            canonicalWorkSHA256: link.canonicalWorkSHA256,
            kind: .unlinkReversal,
            reversesEventID: link.eventID,
            predecessorEventID: link.eventID,
            predecessorEventSHA256: link.eventSHA256,
            revision: 2,
            mutationID: reversalMutationID,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_201)
        )
        try reversal.validateSuccessor(of: link)
        XCTAssertEqual(reversal.kind, .unlinkReversal)
        XCTAssertEqual(reversal.reversesEventID, link.eventID)

        let mutation = try ServiceRequestMutationV1(
            workspaceID: workspace,
            expectedRevision: expected,
            mutationID: mutationID,
            payloads: [.appendWorkLink(link)]
        )
        try mutation.validateForCanonicalWriter()
        XCTAssertEqual(try mutation.affectedIdentities.count, 1)
        XCTAssertEqual(try mutation.concurrencyIdentities.count, 1)
        XCTAssertEqual(WorkspaceCommandV1.applyServiceRequest(mutation).kind, .applyServiceRequest)
        XCTAssertTrue(corpus.workConversion.requiresExplicitChoice)
        XCTAssertTrue(corpus.workConversion.bindsRequestRevision)
        XCTAssertTrue(corpus.workConversion.bindsTargetRevision)
        XCTAssertTrue(corpus.workConversion.usesMutationID)
        XCTAssertTrue(corpus.workConversion.exactlyOneCanonicalLink)
        XCTAssertTrue(corpus.workConversion.unlinkIsAppendOnlyReversal)
        XCTAssertFalse(corpus.workConversion.automaticWorkCreation)
    }

    func testV23P03C52R01BackupRestoreCloneForkEraseAndReplayPreserveRequestHistoryAndInvalidateCapabilities() async throws {
        let corpus = try C52PortableServiceRequestTestSupport.fixture()
        let golden = try C52PortableServiceRequestTestSupport.golden()
        try ServiceRequestPersistenceEnrollmentV1.validate()
        XCTAssertEqual(ServiceRequestPersistenceEnrollmentV1.durableModelCount, 3)
        XCTAssertEqual(ServiceRequestPersistenceEnrollmentV1.durableFamilies.count, 3)
        XCTAssertTrue(ServiceRequestPersistenceEnrollmentV1.registrations.contains {
            $0.kind == "ServiceRequestSubmissionCapabilityV1.rawBytes"
                && $0.classification == .prohibitedPersistent
        })
        XCTAssertTrue(ServiceRequestLifecycleRegistrationBoundaryV1.immutableAcceptedSourceBytesParticipateInBackup)
        XCTAssertTrue(ServiceRequestLifecycleRegistrationBoundaryV1.protectedInvitationMappingParticipatesInBackup)
        XCTAssertTrue(ServiceRequestLifecycleRegistrationBoundaryV1.replaceRestorePreservesHistory)
        XCTAssertTrue(ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkPreservesHistory)
        XCTAssertTrue(ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities)
        XCTAssertTrue(ServiceRequestLifecycleRegistrationBoundaryV1.eraseRemovesOwnedProtectedState)
        XCTAssertFalse(ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled)
        XCTAssertTrue(ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable)
        XCTAssertTrue(ServiceRequestLifecycleRegistrationBoundaryV1.exactlyOneCanonicalWriter)
        XCTAssertTrue(corpus.lifecycle.serviceNamespaceIndependentFromReview)
        XCTAssertTrue(corpus.lifecycle.v1ToV2PreservesBytesIDsTimestampsAndState)
        XCTAssertTrue(corpus.lifecycle.backupPreservesCanonicalHistory)
        XCTAssertTrue(corpus.lifecycle.cloneAndForkPreserveHistory)
        XCTAssertTrue(corpus.lifecycle.cloneAndForkInvalidateOutstandingCapabilities)
        XCTAssertTrue(corpus.lifecycle.eraseRemovesAppOwnedProtectedState)
        XCTAssertTrue(corpus.lifecycle.escapedCopiesCanBeAcknowledgedButNotRecalled)

        let supportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("c52-service-request-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: supportURL) }
        let store = try PortableExchangeSessionStoreV2(applicationSupportURL: supportURL)
        let lifecycle = ServiceRequestLifecycleAdapterV1(store: store)
        let staged = try await lifecycle.stageInvitation(
            golden.invitation,
            release: golden.release,
            workspaceID: C52PortableServiceRequestTestSupport.workspace.rawValue
        )
        XCTAssertEqual(staged.namespace, .serviceRequest)
        XCTAssertEqual(staged.publicRequestID, golden.manifest.invitationPublicID.rawValue)
        XCTAssertEqual(staged.capabilityState, .issuedNotExported)
        let manifestBytes = try await lifecycle.invitationManifest(golden.manifest.invitationPublicID)
        XCTAssertEqual(manifestBytes, .some(try ServiceRequestCanonicalCodecV1.data(golden.manifest)))
        let exported = try await lifecycle.markInvitationExported(golden.manifest.invitationPublicID)
        XCTAssertEqual(exported.state, .exportedAwaitingResponse)

        let lifecyclePreview = try await lifecycle.previewSubmission(
            golden.submission,
            sourceBytes: golden.sourceBytes,
            capability: golden.capability
        )
        XCTAssertEqual(lifecyclePreview.invitationPublicID, golden.manifest.invitationPublicID)
        XCTAssertEqual(lifecyclePreview.submissionPublicID, golden.submission.submissionPublicID)
        XCTAssertEqual(lifecyclePreview.canonicalSourceSHA256, ServiceRequestCanonicalCodecV1.sha256(golden.sourceBytes))
        XCTAssertEqual(lifecyclePreview.capabilityAssessment.proofValidity, .valid)
        XCTAssertEqual(lifecyclePreview.capabilityAssessment.importEligibility, .eligible)
        XCTAssertFalse(lifecyclePreview.submissionAlreadyRecorded)

        let priorRequest = try C52PortableServiceRequestTestSupport.requestReference()
        let duplicateReason = try ServiceRequestDuplicateReasonV1(
            kind: .exactCategory,
            explanation: "Same Site and Asset share the explicit category"
        )
        let duplicateCandidate = try ServiceRequestDuplicateCandidateV1(
            record: priorRequest,
            sharedSiteID: golden.scope.siteID,
            sharedAssetID: golden.scope.assets.first?.assetID,
            reasons: [duplicateReason]
        )
        let duplicateProjection = try ServiceRequestDuplicateProjectionV1(
            basisRequestSHA256: ServiceRequestCanonicalCodecV1.sha256(golden.sourceBytes),
            ruleReleaseSHA256: C52PortableServiceRequestTestSupport.digest("f"),
            candidates: [duplicateCandidate]
        )
        let expectedIdentity = try WorkspaceEntityIdentityV1(
            kind: .serviceRequestRecord,
            id: priorRequest.recordID
        )
        let expectedRevision = try WorkspaceExpectedRevisionV1(
            workspaceID: C52PortableServiceRequestTestSupport.workspace,
            generationID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5350"),
            writerInstanceID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5351"),
            workspaceRevision: 7,
            entityRevisions: [WorkspaceEntityRevisionV1(identity: expectedIdentity, revision: 1)]
        )
        let initialRevision = try WorkspaceRevisionV1(
            workspaceID: expectedRevision.workspaceID,
            generationID: expectedRevision.generationID,
            writerInstanceID: expectedRevision.writerInstanceID,
            revision: expectedRevision.workspaceRevision,
            entityRevisions: expectedRevision.entityRevisions
        )
        let writer = try WorkspaceWriterV1(
            identity: try WorkspaceReplicaIdentityV1(
                workspaceID: expectedRevision.workspaceID,
                replicaID: ReplicaID(
                    rawValue: C52PortableServiceRequestTestSupport.uuid(
                        "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5352"
                    )
                )
            ),
            generationID: expectedRevision.generationID,
            initialRevision: initialRevision,
            clock: C52PortableServiceRequestFixedClock(
                value: Date(timeIntervalSince1970: 1_700_000_203)
            ),
            idSource: C52PortableServiceRequestConstantIDSource(
                value: expectedRevision.writerInstanceID
            ),
            fileAuthority: SystemApplicationFileAuthorityV1(),
            adapter: C52PortableServiceRequestWorkspaceWriterAdapterV1(),
            journalStore: nil
        )
        let coordinator = ServiceRequestCoordinatorV1(
            duplicates: C52PortableServiceRequestDuplicateProjectionProviderV1(
                projection: duplicateProjection
            ),
            writer: writer,
            lifecycle: lifecycle,
            contactPromotion: C52PortableServiceRequestContactPromotionProviderV1(),
            clock: C52PortableServiceRequestFixedClock(
                value: Date(timeIntervalSince1970: 1_700_000_204)
            ),
            idSource: C52PortableServiceRequestSequenceIDSourceV1(values: [
                C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5355"),
                C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5356"),
                C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5357"),
                C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5358"),
                C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5359")
            ])
        )
        let canonicalSource = try CanonicalServiceRequestSourceBytesV1(golden.sourceBytes)
        let linkedPreview = try await coordinator.previewPortableImport(
            expectedRevision: expectedRevision,
            release: golden.release,
            invitation: golden.invitation,
            submission: golden.submission,
            canonicalSourceBytes: canonicalSource,
            disposition: .acceptAndLinkDuplicate,
            selectedDuplicate: priorRequest,
            reason: nil,
            mutationID: try MutationIDV1(
                rawValue: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5360")
            )
        )
        let linkedRecord = try XCTUnwrap(linkedPreview.proposedRecord)
        let linkedEvent = try XCTUnwrap(linkedPreview.proposedDispositionEvent)
        let expectedLinkedRevision = try WorkspaceExpectedRevisionV1(
            workspaceID: expectedRevision.workspaceID,
            generationID: expectedRevision.generationID,
            writerInstanceID: expectedRevision.writerInstanceID,
            workspaceRevision: expectedRevision.workspaceRevision,
            entityRevisions: [
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .serviceRequestRecord,
                        id: linkedRecord.recordID
                    ),
                    revision: 0
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .serviceRequestDispositionEvent,
                        id: linkedEvent.eventID
                    ),
                    revision: 0
                )
            ]
        )
        XCTAssertEqual(linkedPreview.expectedRevision, expectedLinkedRevision)
        XCTAssertEqual(linkedPreview.plan.basisWorkspaceRevision, expectedRevision.workspaceRevision)
        XCTAssertEqual(linkedPreview.plan.selectedDuplicate, .some(priorRequest))
        XCTAssertEqual(linkedEvent.disposition, .acceptAndLinkDuplicate)
        XCTAssertEqual(linkedEvent.resultingState, .openAccepted)
        XCTAssertEqual(linkedRecord.acceptedSourceBytes, .some(canonicalSource))
        try PortableServiceRequestCodecV1.assertRecordBytesExcludeCapability(
            linkedRecord,
            capability: golden.capability
        )

        let newPreview = try await coordinator.previewPortableImport(
            expectedRevision: expectedRevision,
            release: golden.release,
            invitation: golden.invitation,
            submission: golden.submission,
            canonicalSourceBytes: canonicalSource,
            disposition: .acceptAsNew,
            selectedDuplicate: nil,
            reason: nil,
            mutationID: try MutationIDV1(
                rawValue: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5361")
            )
        )
        XCTAssertEqual(newPreview.proposedDispositionEvent?.resultingState, .some(.openAccepted))

        let workPreview = try ServiceRequestCanonicalWorkPreviewV1(
            target: WorkSubjectReferenceV1(
                kind: .asset,
                subjectID: C52PortableServiceRequestTestSupport.assetID,
                revision: 3,
                ownerAssetID: nil
            ),
            choice: .activity(
                activityID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5362"),
                expectedRevision: 1,
                semanticSHA256: C52PortableServiceRequestTestSupport.digest("g")
            ),
            canonicalWorkID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5363"),
            canonicalWorkRevision: 1,
            canonicalWorkSHA256: C52PortableServiceRequestTestSupport.digest("h")
        )
        let workPlan = try coordinator.previewWorkConversion(
            request: try linkedRecord.reference,
            expectedRevision: expectedRevision,
            work: workPreview,
            predecessor: nil,
            mutationID: try MutationIDV1(
                rawValue: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5364")
            )
        )
        let expectedWorkRevision = try WorkspaceExpectedRevisionV1(
            workspaceID: expectedRevision.workspaceID,
            generationID: expectedRevision.generationID,
            writerInstanceID: expectedRevision.writerInstanceID,
            workspaceRevision: expectedRevision.workspaceRevision,
            entityRevisions: [
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .serviceRequestWorkLinkEvent,
                        id: workPlan.event.eventID
                    ),
                    revision: 0
                )
            ]
        )
        XCTAssertEqual(workPlan.expectedRevision, expectedWorkRevision)

        let lifecycleProjectionValue = try await lifecycle.lifecycleProjection(
            for: golden.manifest.invitationPublicID
        )
        let lifecycleProjection = try XCTUnwrap(lifecycleProjectionValue)
        XCTAssertEqual(lifecycleProjection.state, .exportedAwaitingResponse)
        XCTAssertEqual(lifecycleProjection.capabilityState, .exportedAccepting)
        XCTAssertTrue(lifecycleProjection.protectedCapabilityAvailable)
        let lifecycleProjectionValues = try await lifecycle.lifecycleProjections()
        XCTAssertEqual(lifecycleProjectionValues.count, 1)

        let snapshot = try await lifecycle.snapshotForBackup()
        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertEqual(snapshot.protectedCapabilityArtifacts.count, 1)
        XCTAssertEqual(snapshot.protectedCapabilityArtifacts.first?.bytes, golden.capability.rawBytes)

        let cloned = try await lifecycle.markClonedOrForked(
            operationID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5340"),
            resultGenerationID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5341")
        )
        try cloned.validate()
        XCTAssertEqual(cloned.invalidatedSessionCount, 1)
        XCTAssertTrue(cloned.activeCapabilitiesInvalidated)
        let clonedSession = try await lifecycle.serviceRequestSession(golden.manifest.invitationPublicID)
        XCTAssertEqual(
            clonedSession?.state,
            .some(PortableExchangeSessionStateV2.historyOnlyClonedOrForked)
        )
        XCTAssertNil(clonedSession?.protectedCapability)

        let restored = try await lifecycle.replaceRestore(
            with: snapshot,
            operationID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5342")
        )
        try restored.validate()
        XCTAssertEqual(restored.restoredSessionCount, 1)
        XCTAssertEqual(restored.activeCapabilitiesPreserved, 1)
        let erased = try await lifecycle.erase(
            operationID: C52PortableServiceRequestTestSupport.uuid("8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5343")
        )
        try erased.validate()
        XCTAssertEqual(erased.erasedSessionCount, 1)
        XCTAssertEqual(erased.erasedCapabilityCount, 1)
        let erasedLifecycleProjections = try await lifecycle.lifecycleProjections()
        XCTAssertTrue(erasedLifecycleProjections.isEmpty)

        try C52ServiceRequestLocalizationBoundaryV1.validate()
        let localizationRegistry = try BundledLocalizationCatalogV1.serviceRequestRegistry()
        let localizationKeys = Set(localizationRegistry.definitions.map { $0.key.rawValue })
        XCTAssertTrue(C52ServiceRequestLocalizationKeyV1.allCases.allSatisfy {
            localizationKeys.contains($0.rawValue)
        })
        XCTAssertTrue(corpus.localization.englishOnly)
        XCTAssertEqual(corpus.localization.sourceLocale, "en")
        XCTAssertTrue(corpus.localization.deliveryWordsForbidden)
        XCTAssertTrue(corpus.localization.emergencyWordsForbidden)
        XCTAssertTrue(corpus.localization.slaWordsForbidden)
        XCTAssertTrue(corpus.status.customerSafeBoundedArtifact)
        XCTAssertFalse(corpus.privacy.capabilityInReportsLogsSearchAccessibility)
        XCTAssertTrue(corpus.privacy.recipientMediaIsDerivedOnly)
        XCTAssertTrue(corpus.privacy.contactPromotionIsOperationalOnly)
        XCTAssertFalse(C52ServiceRequestCoordinatorBoundaryV1.statusArtifactClaimsDelivery)
    }
}

private extension Data {
    func containsSubsequence(_ subsequence: Data) -> Bool {
        guard !subsequence.isEmpty, subsequence.count <= count else { return false }
        let haystack = Array(self)
        let needle = Array(subsequence)
        for offset in 0...(haystack.count - needle.count) {
            if Array(haystack[offset..<(offset + needle.count)]) == needle {
                return true
            }
        }
        return false
    }
}

private struct C52PortableServiceRequestFixedClock: ApplicationClock {
    let value: Date

    func now() -> Date { value }
}

private struct C52PortableServiceRequestConstantIDSource: ApplicationIDSource {
    let value: UUID

    func makeID() -> UUID { value }
}

private final class C52PortableServiceRequestSequenceIDSourceV1: ApplicationIDSource, @unchecked Sendable {
    private var values: [UUID]

    init(values: [UUID]) {
        self.values = values
    }

    func makeID() -> UUID {
        guard !values.isEmpty else {
            return UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5399")!
        }
        return values.removeFirst()
    }
}

@MainActor
private final class C52PortableServiceRequestDuplicateProjectionProviderV1: ServiceRequestDuplicateProjectingV1 {
    let projection: ServiceRequestDuplicateProjectionV1

    init(projection: ServiceRequestDuplicateProjectionV1) {
        self.projection = projection
    }

    func projectCandidates(
        workspaceID: WorkspaceID,
        submission: PortableServiceRequestSubmissionV1,
        canonicalSourceSHA256: String
    ) throws -> ServiceRequestDuplicateProjectionV1 {
        projection
    }
}

@MainActor
private final class C52PortableServiceRequestContactPromotionProviderV1: ServiceRequestContactPromotionPreviewingV1 {
    func previewOperationalContactPromotion(
        request: ServiceRequestRecordV1,
        party: ServicePartyReferenceV1
    ) throws -> ServiceRequestContactPromotionPreviewV1 {
        throw ServiceRequestCoordinatorFailureV1.contactPromotionUnavailable
    }
}

@MainActor
private final class C52PortableServiceRequestWorkspaceWriterAdapterV1: WorkspaceWriterAdapterPortV1 {
    func apply(
        _ command: WorkspaceCommandV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        throw WorkspaceMutationFailureV1.unsupportedCommand
    }
}

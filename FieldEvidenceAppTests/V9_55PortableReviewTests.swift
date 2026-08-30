import CryptoKit
import Foundation
import XCTest

@testable import FieldEvidenceApp

private struct C48PortableReviewProtocolFixture: Decodable {
    let releaseDigestHex: String
    let hmacAlgorithm: String
    let transcriptDomainASCII: String
    let transcriptDomainNULTerminated: Bool
    let lengthPrefix: String
    let digestEncoding: String
    let requestIDEncoding: String
    let constantTimeVerification: Bool
    let proofCarriesCapability: Bool
    let proofValidityIndependentOfApplicationEligibility: Bool
    let proofValidButStaleCanBeHistoryOnly: Bool
    let capabilityByteCount: Int
}

private struct C48PortableReviewVectorFixture: Decodable {
    let vectorID: String
    let capabilityHex: String
    let requestPublicID: String
    let requestManifestDigestHex: String
    let innerRequestPackageDigestHex: String
    let canonicalResponseBodyDigestHex: String
    let transcriptByteCount: Int
    let transcriptSHA256: String
    let expectedHMACHex: String
    let transcriptHex: String
}

private struct C48PortableReviewRequestArchiveFixture: Decodable {
    let uti: String
    let fileExtension: String
    let members: [String]
    let optionalMemberPrefix: String
    let customerSafeReportRevision: Int
    let requestPublicID: String
    let itemPublicIDs: [String]
    let projectionStates: [String]
    let excludedFromExchange: [String]
}

private struct C48PortableReviewResponseDispositionFixture: Decodable {
    let kind: String
    let terminal: Bool
    let requiresChangeItems: Bool
    let forbidsChangeItems: Bool?
    let projectionAfter: String
}

private struct C48PortableReviewResponseArchiveFixture: Decodable {
    let uti: String
    let fileExtension: String
    let canonicalDocumentCount: Int
    let textOnly: Bool
    let attachmentsAllowed: Bool
    let executableContentAllowed: Bool
    let responsePublicID: String
    let requestPublicID: String
    let responseItemPublicIDs: [String]
    let dispositions: [C48PortableReviewResponseDispositionFixture]
}

private struct C48PortableReviewAcquisitionFixture: Decodable {
    let kinds: [String]
    let originRecordedElsewhereSource: String
    let requiresExistingExportedRequest: Bool
    let fabricatesCapabilityProof: Bool
    let fabricatesResponseFile: Bool
    let trustClaims: [String]
    let forbiddenTrustClaims: [String]
}

private struct C48PortableReviewPreviewFixture: Decodable {
    let zeroWrite: Bool
    let repeatable: Bool
    let canonicalWriteCount: Int
    let receiptCount: Int
    let projectionChanges: Int
    let quarantineIsCanonical: Bool
}

private struct C48PortableReviewApplyFixture: Decodable {
    let rechecksCurrentRevision: Bool
    let promotesExactResponseBytes: Bool
    let recordsExternalResponse: Bool
    let recordsDecisionReceipt: Bool
    let invokesExistingReviewTruth: Bool
    let recordsSelfAssertedActorSnapshot: Bool
    let updatesProjectionAtomically: Bool
    let automaticFinalization: Bool
}

private struct C48PortableReviewImportFixture: Decodable {
    let dispositions: [String]
    let decisions: [String]
    let preview: C48PortableReviewPreviewFixture
    let acceptAndApply: C48PortableReviewApplyFixture
    let staleResponseDisposition: String
    let sameResponseIDExactReplayIdempotent: Bool
    let divergentSameResponseIDQuarantined: Bool
    let noOverwriteOnDivergence: Bool
    let conflictsPreserved: Bool
}

private struct C48PortableReviewInterruptionFixture: Decodable {
    let boundaries: [String]
    let disposition: String
    let retryDisposition: String
}

private struct C48PortableReviewLifecycleFixture: Decodable {
    let capabilityStates: [String]
    let restoreModes: [String]
    let historicReadExport: Bool
    let exactBytesImmutableAfterAcceptance: Bool
    let eraseRemoves: [String]
    let eraseCannotRecallSharedFiles: Bool
    let namespaces: [String]
    let namespaceQuotasIndependent: Bool
    let searchIncludesSecrets: Bool
    let diagnosticsIncludeSecrets: Bool
    let accessibilitySpeechIncludesSecrets: Bool
}

private struct C48PortableReviewCompatibilityFixture: Decodable {
    let releasedV1BytesPreserved: Bool
    let historicReaderRequired: Bool
    let historicBytesMigratedInPlace: Bool
    let successorRequestGetsNewID: Bool
    let successorRequestGetsNewCapability: Bool
    let successorRequestGetsNewDigest: Bool
}

private struct C48PortableReviewCorpusFixture: Decodable {
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
    let protocolFixture: C48PortableReviewProtocolFixture
    let normativeVectors: [C48PortableReviewVectorFixture]
    let requestArchive: C48PortableReviewRequestArchiveFixture
    let responseArchive: C48PortableReviewResponseArchiveFixture
    let acquisition: C48PortableReviewAcquisitionFixture
    let importFixture: C48PortableReviewImportFixture
    let proofMutationCases: [String]
    let hostileArchiveCases: [String]
    let leakageCanaries: [String]
    let interruption: C48PortableReviewInterruptionFixture
    let lifecycle: C48PortableReviewLifecycleFixture
    let compatibility: C48PortableReviewCompatibilityFixture

    private enum CodingKeys: String, CodingKey {
        case schema, schemaVersion, cardID, corpusID, testOnly, synthetic, immutable
        case containsCustomerData, containsSecrets, contracts
        case protocolFixture = "protocol"
        case normativeVectors, requestArchive, responseArchive, acquisition
        case importFixture = "import"
        case proofMutationCases, hostileArchiveCases, leakageCanaries
        case interruption, lifecycle, compatibility
    }
}

private enum C48PortableReviewTestFailure: Error {
    case missingFixture
    case malformedHex
}

private enum C48PortableReviewTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    static func fixture() throws -> C48PortableReviewCorpusFixture {
        let bundle = Bundle(for: V9_55PortableReviewTests.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V22P03C48PortableReviewCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V22/ReviewExchange"
            ) ?? bundle.url(
                forResource: "V22P03C48PortableReviewCorpusV1",
                withExtension: "json"
            ),
            "Missing V22 P03 C48 portable-review corpus"
        )
        return try JSONDecoder().decode(
            C48PortableReviewCorpusFixture.self,
            from: Data(contentsOf: url, options: .mappedIfSafe)
        )
    }

    static func hex(_ value: String) throws -> Data {
        let characters = Array(value)
        guard characters.count.isMultiple(of: 2) else { throw C48PortableReviewTestFailure.malformedHex }
        var result = Data()
        result.reserveCapacity(characters.count / 2)
        for offset in stride(from: 0, to: characters.count, by: 2) {
            let pair = String(characters[offset...offset + 1])
            guard let byte = UInt8(pair, radix: 16) else {
                throw C48PortableReviewTestFailure.malformedHex
            }
            result.append(byte)
        }
        return result
    }

    static func hex(_ value: some Sequence<UInt8>) -> String {
        value.map { String(format: "%02x", $0) }.joined()
    }

    static func transcript(
        domain: String,
        protocolDigest: Data,
        requestID: String,
        requestManifestDigest: Data,
        innerPackageDigest: Data,
        responseBodyDigest: Data
    ) throws -> Data {
        guard let domainBytes = domain.data(using: .ascii),
              let requestIDBytes = requestID.data(using: .ascii) else {
            throw C48PortableReviewTestFailure.malformedHex
        }
        var result = Data(domainBytes)
        result.append(0)
        for field in [
            protocolDigest,
            requestIDBytes,
            requestManifestDigest,
            innerPackageDigest,
            responseBodyDigest
        ] {
            guard field.count <= Int(UInt32.max) else {
                throw C48PortableReviewTestFailure.malformedHex
            }
            var length = UInt32(field.count).bigEndian
            withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
            result.append(field)
        }
        return result
    }

    static func input(
        vector: C48PortableReviewVectorFixture,
        protocolDigest: Data? = nil,
        requestID: String? = nil,
        requestManifestDigest: Data? = nil,
        innerPackageDigest: Data? = nil,
        responseBodyDigest: Data? = nil
    ) throws -> ReviewCapabilityProofInputV1 {
        try ReviewCapabilityProofInputV1(
            protocolReleaseDigest: protocolDigest ?? hex(vector.releaseDigestHex),
            requestPublicID: try ReviewRequestPublicIDV1(requestID ?? vector.requestPublicID),
            requestManifestDigest: requestManifestDigest ?? hex(vector.requestManifestDigestHex),
            innerRequestPackageDigest: innerPackageDigest ?? hex(vector.innerRequestPackageDigestHex),
            canonicalResponseBodyDigest: responseBodyDigest ?? hex(vector.canonicalResponseBodyDigestHex)
        )
    }

    static func flipped(_ data: Data, at offset: Int = 0) -> Data {
        var bytes = Array(data)
        bytes[offset] ^= 0x01
        return Data(bytes)
    }

    static func withoutByte(_ data: Data, at offset: Int) -> Data {
        var bytes = Array(data)
        bytes.remove(at: offset)
        return Data(bytes)
    }

    static func hmacHex(capability: Data, transcript: Data) -> String {
        let code = HMAC<SHA256>.authenticationCode(
            for: transcript,
            using: SymmetricKey(data: capability)
        )
        return hex(code)
    }

    static func response(
        vector: C48PortableReviewVectorFixture,
        staged: PortableExchangeSessionRecordV2,
        responsePublicID: String,
        body: ReviewResponseBodyV1,
        proof: ReviewCapabilityProofV1? = nil
    ) throws -> ReviewResponseEnvelopeV1 {
        guard let protocolDigest = staged.protocolReleaseDigest,
              let manifestDigest = staged.requestManifestSHA256,
              let packageDigest = staged.requestPackageSHA256 else {
            throw C48PortableReviewTestFailure.malformedHex
        }
        let input = try ReviewCapabilityProofInputV1(
            protocolReleaseDigest: protocolDigest,
            requestPublicID: try ReviewRequestPublicIDV1(staged.publicRequestID),
            requestManifestDigest: try hex(manifestDigest),
            innerRequestPackageDigest: try hex(packageDigest),
            canonicalResponseBodyDigest: try hex(vector.canonicalResponseBodyDigestHex)
        )
        let productionVector = try ReviewCapabilityProofVectorV1.rv1001()
        let responseProof: ReviewCapabilityProofV1
        if let proof {
            responseProof = proof
        } else {
            responseProof = try ReviewCapabilityProofCodecV1.makeProof(
                capability: productionVector.capability,
                input: input
            )
        }
        return try ReviewResponseEnvelopeV1(
            responsePublicID: responsePublicID,
            requestPublicID: try ReviewRequestPublicIDV1(staged.publicRequestID),
            body: body,
            proof: responseProof,
            canonicalBodyDigest: input.canonicalResponseBodyDigest
        )
    }
}

final class V9_55PortableReviewTests: XCTestCase {
    func testV23P03C48G01GoldenRequestResponseAndNormativeVectorUseTypedContracts() throws {
        let corpus = try C48PortableReviewTestSupport.fixture()
        XCTAssertEqual(corpus.schema, "V22P03C48PortableReviewCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P03-C48")
        XCTAssertTrue(corpus.testOnly)
        XCTAssertTrue(corpus.synthetic)
        XCTAssertTrue(corpus.immutable)
        XCTAssertFalse(corpus.containsCustomerData)
        XCTAssertFalse(corpus.containsSecrets)
        XCTAssertEqual(
            corpus.contracts,
            [
                "PortableReviewProtocolReleaseV1",
                "BearerResponseCapabilityV1",
                "ReviewCapabilityProofV1",
                "ReviewResponseAcquisitionKindV1",
                "OriginRecordedReviewResponseV1",
                "ReviewRequestManifestV1",
                "ReviewSubjectSnapshotBindingV1",
                "ReviewRequestPurposeV1",
                "ReviewRequestFileEntryV1",
                "ReviewResponseEnvelopeV1",
                "ReviewResponseBodyV1",
                "ReviewResponseItemV1",
                "ResponseAuthorAssertionV1",
                "RecipientReviewRequestEventV1",
                "ReviewRequestExportReceiptV1",
                "ExternalReviewResponseRecordV1",
                "ExternalReviewImportPlanV1",
                "ExternalReviewImportDecisionV1",
                "ExternalReviewImportReceiptV1",
                "ReviewRequestStateProjectionV1",
                "ReviewExchangeBudgetV1",
                "PortableExchangeSessionStoreV2"
            ]
        )

        let vector = try XCTUnwrap(corpus.normativeVectors.first)
        XCTAssertEqual(vector.vectorID, "RV1-001")
        XCTAssertEqual(corpus.normativeVectors.count, 1)
        XCTAssertEqual(corpus.protocolFixture.hmacAlgorithm, "HMAC-SHA256-CRYPTOKIT")
        XCTAssertEqual(corpus.protocolFixture.transcriptDomainASCII, ReviewCapabilityProofCodecV1.domain)
        XCTAssertTrue(corpus.protocolFixture.transcriptDomainNULTerminated)
        XCTAssertEqual(corpus.protocolFixture.lengthPrefix, "UInt32BE")
        XCTAssertEqual(corpus.protocolFixture.digestEncoding, "RAW_32_BYTES")
        XCTAssertEqual(corpus.protocolFixture.requestIDEncoding, "CANONICAL_ASCII_NO_NUL")
        XCTAssertTrue(corpus.protocolFixture.constantTimeVerification)
        XCTAssertFalse(corpus.protocolFixture.proofCarriesCapability)
        XCTAssertTrue(corpus.protocolFixture.proofValidityIndependentOfApplicationEligibility)
        XCTAssertTrue(corpus.protocolFixture.proofValidButStaleCanBeHistoryOnly)
        XCTAssertEqual(corpus.protocolFixture.capabilityByteCount, PortableReviewLimitsV1.capabilityByteCount)

        let productionVector = try ReviewCapabilityProofVectorV1.rv1001()
        let productionTranscript = try ReviewCapabilityProofCodecV1.transcript(for: productionVector.input)
        XCTAssertEqual(productionTranscript.count, vector.transcriptByteCount)
        XCTAssertEqual(vector.transcriptByteCount, 236)
        XCTAssertEqual(vector.transcriptSHA256, "5ab5c377885c524b13b17985b5782c34937ada353916c7861a7da97a23c0f0e6")
        XCTAssertEqual(vector.expectedHMACHex, "fb0b14df9c1bdbf6f19222ab40954b07a5c847eca3c5095a3cc379ff6fa5501d")
        XCTAssertEqual(C48PortableReviewTestSupport.hex(productionTranscript), vector.transcriptHex)
        XCTAssertEqual(
            C48PortableReviewTestSupport.hex(SHA256.hash(data: productionTranscript)),
            vector.transcriptSHA256
        )
        XCTAssertEqual(
            C48PortableReviewTestSupport.hex(productionVector.proof.rawBytes),
            vector.expectedHMACHex
        )
        XCTAssertEqual(ReviewCapabilityProofVectorV1.rv1001TranscriptSHA256Hex, vector.transcriptSHA256)
        XCTAssertEqual(ReviewCapabilityProofVectorV1.rv1001HMACSHA256Hex, vector.expectedHMACHex)
        XCTAssertTrue(try ReviewCapabilityProofVectorV1.validatesRV1001())
        XCTAssertTrue(
            try ReviewCapabilityProofCodecV1.verify(
                productionVector.proof,
                capability: productionVector.capability,
                input: productionVector.input
            )
        )

        let release = try PortableReviewProtocolReleaseV1(
            releaseID: "portable-review-v1",
            releaseDigest: productionVector.input.protocolReleaseDigest
        )
        let request = try ReviewRequestManifestV1(
            requestPublicID: productionVector.input.requestPublicID,
            protocolRelease: release,
            requestManifestDigest: productionVector.input.requestManifestDigest,
            innerRequestPackageDigest: productionVector.input.innerRequestPackageDigest
        )
        XCTAssertEqual(
            try request.proofInput(
                canonicalResponseBodyDigest: productionVector.input.canonicalResponseBodyDigest
            ),
            productionVector.input
        )
        XCTAssertEqual(
            corpus.requestArchive.members,
            [
                ReviewRequestFileEntryV1.manifest.rawValue,
                ReviewRequestFileEntryV1.request.rawValue,
                ReviewRequestFileEntryV1.responseCapability.rawValue,
                ReviewRequestFileEntryV1.reportPDF.rawValue,
                ReviewRequestFileEntryV1.reportText.rawValue
            ]
        )
        XCTAssertEqual(corpus.requestArchive.uti, "com.assetrounds.review-request")
        XCTAssertEqual(corpus.requestArchive.fileExtension, ".arreviewrequest")
        XCTAssertEqual(corpus.requestArchive.optionalMemberPrefix, "media/")
        XCTAssertGreaterThan(corpus.requestArchive.customerSafeReportRevision, 0)
        XCTAssertEqual(corpus.requestArchive.requestPublicID, productionVector.input.requestPublicID.rawValue)
        XCTAssertEqual(corpus.responseArchive.uti, "com.assetrounds.review-response")
        XCTAssertEqual(corpus.responseArchive.fileExtension, ".arreviewresponse")
        XCTAssertEqual(corpus.responseArchive.canonicalDocumentCount, 1)
        XCTAssertTrue(corpus.responseArchive.textOnly)
        XCTAssertFalse(corpus.responseArchive.attachmentsAllowed)
        XCTAssertFalse(corpus.responseArchive.executableContentAllowed)
        XCTAssertEqual(
            ReviewResponseDispositionV1.allCases.map(\.rawValue),
            ["ACKNOWLEDGED", "APPROVED", "CHANGES_REQUESTED"]
        )
    }

    func testV23P03C48A01OriginRecordedElsewhereKeepsUnverifiedHistorySeparateFromEligibility() throws {
        let corpus = try C48PortableReviewTestSupport.fixture()
        XCTAssertEqual(
            Set(corpus.acquisition.kinds),
            Set([
                ReviewResponseAcquisitionKindV1.portableFile.rawValue,
                ReviewResponseAcquisitionKindV1.originRecordedElsewhere.rawValue
            ])
        )
        XCTAssertEqual(
            corpus.acquisition.originRecordedElsewhereSource,
            ResponseAuthorAssertionSourceV1.originUserAssertionUnverified.rawValue
        )
        XCTAssertTrue(corpus.acquisition.requiresExistingExportedRequest)
        XCTAssertFalse(corpus.acquisition.fabricatesCapabilityProof)
        XCTAssertFalse(corpus.acquisition.fabricatesResponseFile)
        XCTAssertEqual(corpus.acquisition.trustClaims, ["Response recorded", "Not verified by AssetRounds", "Response proof verified for this request"])

        let requestID = try ReviewRequestPublicIDV1(corpus.requestArchive.requestPublicID)
        let author = try ResponseAuthorAssertionV1(
            displayName: "Origin recorder",
            organization: "Example organization",
            source: .originUserAssertionUnverified,
            statedResponseAt: C48PortableReviewTestSupport.fixedDate,
            statedTimeZoneIdentifier: "UTC"
        )
        let body = try ReviewResponseBodyV1(disposition: .acknowledged, author: author)
        let origin = try OriginRecordedReviewResponseV1(
            requestPublicID: requestID,
            responseBody: body,
            sourceWording: "Recorded at origin from an external conversation; not verified by AssetRounds.",
            recordedByActorID: UUID(uuidString: "48000000-0000-4000-8000-000000000001")!,
            recordedAt: C48PortableReviewTestSupport.fixedDate
        )
        try origin.validate()
        XCTAssertEqual(origin.acquisitionKind, .originRecordedElsewhere)
        XCTAssertEqual(origin.responseBody.author.source, .originUserAssertionUnverified)
        XCTAssertEqual(origin.requestPublicID, requestID)

        let assessment = ReviewProofAssessmentV1(
            proofValidity: .valid,
            applicationEligibility: .stale
        )
        XCTAssertEqual(assessment.proofValidity, .valid)
        XCTAssertEqual(assessment.applicationEligibility, .stale)
        XCTAssertTrue(corpus.protocolFixture.proofValidityIndependentOfApplicationEligibility)
        XCTAssertTrue(corpus.protocolFixture.proofValidButStaleCanBeHistoryOnly)
        XCTAssertEqual(corpus.importFixture.staleResponseDisposition, ExternalReviewImportDecisionV1.recordAsHistoryOnly.rawValue)

        let projection = try ReviewRequestStateProjectionV1(
            requestPublicID: requestID,
            state: .acknowledgedAwaitingDecision,
            lifecycleState: .responsePendingDecision,
            latestResponsePublicID: nil
        )
        XCTAssertEqual(projection.state, .acknowledgedAwaitingDecision)
        XCTAssertEqual(projection.lifecycleState, .responsePendingDecision)
        XCTAssertNil(projection.latestResponsePublicID)
        XCTAssertTrue(corpus.lifecycle.historicReadExport)
    }

    func testV23P03C48H01TamperReplayDivergenceHostileArchiveAndLeakageCanariesFailClosed() throws {
        let corpus = try C48PortableReviewTestSupport.fixture()
        let vector = try XCTUnwrap(corpus.normativeVectors.first)
        let productionVector = try ReviewCapabilityProofVectorV1.rv1001()
        let capability = productionVector.capability.rawBytes
        let input = productionVector.input
        let proof = productionVector.proof

        XCTAssertEqual(
            corpus.proofMutationCases,
            [
                "DOMAIN_BIT_FLIP", "DOMAIN_NUL_REMOVED", "LENGTH_PREFIX_BIT_FLIP",
                "PROTOCOL_DIGEST_BIT_FLIP", "REQUEST_ID_BIT_FLIP", "REQUEST_ID_ALTERNATE_UUID_SPELLING",
                "REQUEST_MANIFEST_DIGEST_BIT_FLIP", "INNER_PACKAGE_DIGEST_BIT_FLIP",
                "RESPONSE_BODY_DIGEST_BIT_FLIP", "RAW_DIGEST_REPLACED_WITH_HEX_ASCII",
                "CAPABILITY_BIT_FLIP", "PROOF_BIT_FLIP", "TRUNCATED_TRANSCRIPT",
                "EXTENDED_TRANSCRIPT", "REORDERED_FIELDS"
            ]
        )
        XCTAssertEqual(
            corpus.hostileArchiveCases,
            [
                "PATH_TRAVERSAL", "ABSOLUTE_PATH", "DUPLICATE_MEMBER", "CASE_COLLISION", "SYMLINK_MEMBER",
                "HARDLINK_MEMBER", "ZIP_BOMB", "OVERSIZE_MEMBER", "UNSUPPORTED_CONTENT", "ACTIVE_HTML",
                "ACTIVE_SCRIPT", "FORM", "MACRO", "UNKNOWN_PROTOCOL_VERSION", "WRONG_REQUEST",
                "WRONG_REPORT", "WRONG_ITEM", "FORWARDED_PACKET", "TWO_TERMINAL_RESPONSES", "LOW_STORAGE",
                "PROTECTED_DATA_LOCK", "CONCURRENT_LOCAL_AMENDMENT"
            ]
        )

        let baseTranscript = try ReviewCapabilityProofCodecV1.transcript(for: input)
        let domainLength = ReviewCapabilityProofCodecV1.domain.utf8.count
        var mutationOffsets = [0, domainLength]
        var fieldOffset = domainLength + 1
        for field in [
            input.protocolReleaseDigest,
            Data(input.requestPublicID.rawValue.utf8),
            input.requestManifestDigest,
            input.innerRequestPackageDigest,
            input.canonicalResponseBodyDigest
        ] {
            mutationOffsets.append(fieldOffset)
            fieldOffset += 4
            mutationOffsets.append(fieldOffset)
            fieldOffset += field.count
        }
        for offset in mutationOffsets {
            XCTAssertNotEqual(
                C48PortableReviewTestSupport.hmacHex(
                    capability: capability,
                    transcript: C48PortableReviewTestSupport.flipped(baseTranscript, at: offset)
                ),
                vector.expectedHMACHex,
                "single-bit mutation at transcript offset \(offset) must not verify"
            )
        }
        XCTAssertNotEqual(
            C48PortableReviewTestSupport.hmacHex(
                capability: capability,
                transcript: C48PortableReviewTestSupport.withoutByte(baseTranscript, at: domainLength)
            ),
            vector.expectedHMACHex
        )
        var extendedTranscript = baseTranscript
        extendedTranscript.append(0)
        XCTAssertNotEqual(
            C48PortableReviewTestSupport.hmacHex(capability: capability, transcript: extendedTranscript),
            vector.expectedHMACHex
        )
        var reorderedTranscript = Data(ReviewCapabilityProofCodecV1.domain.utf8)
        reorderedTranscript.append(0)
        let reorderedFields = [
            input.requestManifestDigest,
            input.protocolReleaseDigest,
            Data(input.requestPublicID.rawValue.utf8),
            input.innerRequestPackageDigest,
            input.canonicalResponseBodyDigest
        ]
        for field in reorderedFields {
            var length = UInt32(field.count).bigEndian
            withUnsafeBytes(of: &length) { reorderedTranscript.append(contentsOf: $0) }
            reorderedTranscript.append(field)
        }
        XCTAssertNotEqual(
            C48PortableReviewTestSupport.hmacHex(capability: capability, transcript: reorderedTranscript),
            vector.expectedHMACHex
        )

        let rawVsHexInput = try C48PortableReviewTestSupport.input(
            vector: vector,
            requestManifestDigest: Data(vector.requestManifestDigestHex.utf8)
        )
        XCTAssertNotEqual(
            try ReviewCapabilityProofCodecV1.makeProof(capability: productionVector.capability, input: rawVsHexInput),
            proof
        )
        let alternateIDInput = try C48PortableReviewTestSupport.input(
            vector: vector,
            requestID: vector.requestPublicID.uppercased()
        )
        XCTAssertNotEqual(
            try ReviewCapabilityProofCodecV1.makeProof(capability: productionVector.capability, input: alternateIDInput),
            proof
        )
        let tamperedCapability = try BearerResponseCapabilityV1(rawBytes: C48PortableReviewTestSupport.flipped(capability))
        XCTAssertNotEqual(
            try ReviewCapabilityProofCodecV1.makeProof(capability: tamperedCapability, input: input),
            proof
        )
        let tamperedProof = try ReviewCapabilityProofV1(rawBytes: C48PortableReviewTestSupport.flipped(proof.rawBytes))
        XCTAssertFalse(try ReviewCapabilityProofCodecV1.verify(tamperedProof, capability: productionVector.capability, input: input))
        XCTAssertTrue(ReviewCapabilityProofCodecV1.constantTimeEqual(proof.rawBytes, proof.rawBytes))
        XCTAssertFalse(ReviewCapabilityProofCodecV1.constantTimeEqual(proof.rawBytes, tamperedProof.rawBytes))
        XCTAssertFalse(ReviewCapabilityProofCodecV1.constantTimeEqual(proof.rawBytes, Data(repeating: 0, count: 31)))

        XCTAssertThrowsError(try BearerResponseCapabilityV1(rawBytes: Data(repeating: 0, count: 31))) { error in
            XCTAssertEqual(error as? PortableReviewFailureV1, .invalidCapability)
        }
        XCTAssertThrowsError(try ReviewCapabilityProofV1(rawBytes: Data(repeating: 0, count: 31))) { error in
            XCTAssertEqual(error as? PortableReviewFailureV1, .invalidProof)
        }
        XCTAssertThrowsError(try ReviewRequestPublicIDV1("é")) { error in
            XCTAssertEqual(error as? PortableReviewFailureV1, .nonCanonicalEncoding)
        }
        XCTAssertThrowsError(try ReviewRequestPublicIDV1("review-request-\u{0000}")) { error in
            XCTAssertEqual(error as? PortableReviewFailureV1, .nonCanonicalEncoding)
        }
        XCTAssertThrowsError(
            try PortableReviewProtocolReleaseV1(
                releaseID: "portable-review-v2",
                releaseDigest: Data(repeating: 0, count: 32),
                proofProfile: "UNKNOWN_PROFILE"
            )
        ) { error in
            XCTAssertEqual(error as? PortableReviewFailureV1, .unsupportedProtocol)
        }
        let author = try ResponseAuthorAssertionV1(displayName: "Reviewer")
        XCTAssertThrowsError(try ReviewResponseBodyV1(disposition: .approved, changeItems: ["change"], author: author)) { error in
            XCTAssertEqual(error as? PortableReviewFailureV1, .invalidValue)
        }
        XCTAssertThrowsError(try ReviewResponseBodyV1(disposition: .changesRequested, author: author)) { error in
            XCTAssertEqual(error as? PortableReviewFailureV1, .invalidValue)
        }
        XCTAssertThrowsError(try ResponseAuthorAssertionV1(displayName: "bad\nname")) { error in
            XCTAssertEqual(error as? PortableReviewFailureV1, .invalidValue)
        }
        XCTAssertThrowsError(try ResponseAuthorAssertionV1(displayName: "Reviewer", statedTimeZoneIdentifier: "Mars/Phobos")) { error in
            XCTAssertEqual(error as? PortableReviewFailureV1, .invalidValue)
        }

        let safeSurface = corpus.acquisition.trustClaims.joined(separator: "\n")
        XCTAssertFalse(safeSurface.contains(vector.capabilityHex))
        XCTAssertFalse(safeSurface.contains(vector.expectedHMACHex))
        XCTAssertFalse(safeSurface.localizedCaseInsensitiveContains("WorkspaceID"))
        XCTAssertFalse(safeSurface.localizedCaseInsensitiveContains("ReplicaID"))
        XCTAssertFalse(safeSurface.localizedCaseInsensitiveContains("filesystem"))
        XCTAssertFalse(safeSurface.localizedCaseInsensitiveContains("diagnostic"))
        XCTAssertFalse(safeSurface.localizedCaseInsensitiveContains("customer approved"))
        for claim in corpus.acquisition.forbiddenTrustClaims {
            XCTAssertFalse(
                corpus.acquisition.trustClaims.contains { $0.localizedCaseInsensitiveContains(claim) },
                "forbidden trust claim escaped into accepted copy: \(claim)"
            )
        }
        XCTAssertTrue(corpus.requestArchive.excludedFromExchange.contains("WorkspaceID"))
        XCTAssertTrue(corpus.requestArchive.excludedFromExchange.contains("ReplicaID"))
        XCTAssertTrue(corpus.requestArchive.excludedFromExchange.contains("raw originals"))
    }

    func testV23P03C48I01PreviewIsZeroWriteAndEveryCrashBoundaryConvergesToZeroOrComplete() async throws {
        let corpus = try C48PortableReviewTestSupport.fixture()
        XCTAssertEqual(
            corpus.interruption.boundaries,
            [
                "REQUEST_RENDER", "REQUEST_SEAL", "REQUEST_SHARE", "RESPONSE_SEAL",
                "QUARANTINE_VALIDATION", "PREVIEW", "CONTENT_PROMOTION", "CANONICAL_EFFECT", "RECEIPT"
            ]
        )
        XCTAssertEqual(corpus.interruption.disposition, "ZERO_OR_COMPLETE")
        XCTAssertEqual(corpus.interruption.retryDisposition, "EXACT_EFFECT_AND_RECEIPT_OR_NO_EFFECT")
        XCTAssertTrue(corpus.importFixture.preview.zeroWrite)
        XCTAssertTrue(corpus.importFixture.preview.repeatable)
        XCTAssertEqual(corpus.importFixture.preview.canonicalWriteCount, 0)
        XCTAssertEqual(corpus.importFixture.preview.receiptCount, 0)
        XCTAssertEqual(corpus.importFixture.preview.projectionChanges, 0)
        XCTAssertFalse(corpus.importFixture.preview.quarantineIsCanonical)
        XCTAssertTrue(corpus.importFixture.acceptAndApply.rechecksCurrentRevision)
        XCTAssertTrue(corpus.importFixture.acceptAndApply.promotesExactResponseBytes)
        XCTAssertTrue(corpus.importFixture.acceptAndApply.recordsExternalResponse)
        XCTAssertTrue(corpus.importFixture.acceptAndApply.recordsDecisionReceipt)
        XCTAssertTrue(corpus.importFixture.acceptAndApply.invokesExistingReviewTruth)
        XCTAssertTrue(corpus.importFixture.acceptAndApply.recordsSelfAssertedActorSnapshot)
        XCTAssertTrue(corpus.importFixture.acceptAndApply.updatesProjectionAtomically)
        XCTAssertFalse(corpus.importFixture.acceptAndApply.automaticFinalization)
        XCTAssertEqual(
            Set(corpus.importFixture.decisions),
            Set(ExternalReviewImportDecisionV1.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            Set(corpus.importFixture.dispositions),
            Set(ExternalReviewImportDispositionV1.allCases.map(\.rawValue))
        )
        let budget = try ReviewExchangeBudgetV1()
        XCTAssertEqual(budget.maximumSessions, PortableReviewLimitsV1.maximumExchangeSessions)
        XCTAssertEqual(budget.maximumResponseBytes, PortableReviewLimitsV1.maximumResponseBytes)
        try await assertC48SessionStorePreviewApplyReplayAndDivergence()
    }

    func testV23P03C48R01RestoreCloneForkEraseAndReplayPreserveHistoricBytesAndInvalidateActiveCapability() async throws {
        let corpus = try C48PortableReviewTestSupport.fixture()
        XCTAssertEqual(
            Set(corpus.lifecycle.capabilityStates),
            Set(PortableReviewLifecycleStateV1.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            corpus.lifecycle.restoreModes,
            [
                "REPLACE_PRESERVES_OPEN_CAPABILITY",
                "CLONE_HISTORY_ONLY_INVALIDATES_ACTIVE_CAPABILITY",
                "FORK_HISTORY_ONLY_INVALIDATES_ACTIVE_CAPABILITY",
                "OLDER_RESTORE_REQUIRES_RECONCILIATION"
            ]
        )
        XCTAssertTrue(corpus.lifecycle.historicReadExport)
        XCTAssertTrue(corpus.lifecycle.exactBytesImmutableAfterAcceptance)
        XCTAssertEqual(
            corpus.lifecycle.eraseRemoves,
            ["local mappings", "capability secrets", "quarantine scratch", "exchange sessions"]
        )
        XCTAssertTrue(corpus.lifecycle.eraseCannotRecallSharedFiles)
        XCTAssertEqual(corpus.lifecycle.namespaces, ["REVIEW", "SERVICE_REQUEST"])
        XCTAssertTrue(corpus.lifecycle.namespaceQuotasIndependent)
        XCTAssertFalse(corpus.lifecycle.searchIncludesSecrets)
        XCTAssertFalse(corpus.lifecycle.diagnosticsIncludeSecrets)
        XCTAssertFalse(corpus.lifecycle.accessibilitySpeechIncludesSecrets)
        XCTAssertTrue(corpus.compatibility.releasedV1BytesPreserved)
        XCTAssertTrue(corpus.compatibility.historicReaderRequired)
        XCTAssertFalse(corpus.compatibility.historicBytesMigratedInPlace)
        XCTAssertTrue(corpus.compatibility.successorRequestGetsNewID)
        XCTAssertTrue(corpus.compatibility.successorRequestGetsNewCapability)
        XCTAssertTrue(corpus.compatibility.successorRequestGetsNewDigest)
        XCTAssertTrue(corpus.importFixture.sameResponseIDExactReplayIdempotent)
        XCTAssertTrue(corpus.importFixture.divergentSameResponseIDQuarantined)
        XCTAssertTrue(corpus.importFixture.noOverwriteOnDivergence)
        XCTAssertTrue(corpus.importFixture.conflictsPreserved)

        let requestID = try ReviewRequestPublicIDV1(corpus.requestArchive.requestPublicID)
        let vector = try ReviewCapabilityProofVectorV1.rv1001()
        let responseAuthor = try ResponseAuthorAssertionV1(displayName: "External reviewer")
        let responseBody = try ReviewResponseBodyV1(
            disposition: .acknowledged,
            author: responseAuthor
        )
        let response = try ReviewResponseEnvelopeV1(
            responsePublicID: corpus.responseArchive.responsePublicID,
            requestPublicID: requestID,
            body: responseBody,
            proof: vector.proof,
            canonicalBodyDigest: vector.input.canonicalResponseBodyDigest
        )
        let workspaceID = WorkspaceID(rawValue: UUID(uuidString: "48000000-0000-4000-8000-000000000010")!)
        let release = try PortableReviewProtocolReleaseV1(
            releaseID: "portable-review-v1",
            releaseDigest: vector.input.protocolReleaseDigest
        )
        let requestManifest = try ReviewRequestManifestV1(
            requestPublicID: requestID,
            protocolRelease: release,
            requestManifestDigest: vector.input.requestManifestDigest,
            innerRequestPackageDigest: vector.input.innerRequestPackageDigest
        )
        let proofAssessment = ReviewProofAssessmentV1(
            proofValidity: .valid,
            applicationEligibility: .stale
        )
        let responseRecord = try ExternalReviewResponseRecordV1(
            recordID: UUID(uuidString: "48000000-0000-4000-8000-000000000011")!,
            workspaceID: workspaceID,
            requestManifest: requestManifest,
            canonicalResponse: try CanonicalReviewResponseBytesV1(response: response),
            source: .portableFile,
            proofAssessment: proofAssessment,
            recordedAt: C48PortableReviewTestSupport.fixedDate
        )
        let subject = try InspectionReviewSubjectReferenceV1(
            workspaceID: workspaceID,
            kind: .completedActivitySnapshot,
            subjectID: "snapshot-1",
            subjectRevision: 1,
            subjectSHA256: String(repeating: "a", count: 64)
        )
        let item = try ChangeRequestItemReferenceV1(
            kind: .review,
            itemID: "review-item-1",
            itemRevision: 1,
            itemSHA256: String(repeating: "b", count: 64)
        )
        let mapping = try ReviewRequestC14SubjectItemMappingV1(
            workspaceID: workspaceID,
            requestPublicID: requestID,
            subject: subject,
            items: [item]
        )
        let mutationID = try MutationIDV1(
            rawValue: UUID(uuidString: "48000000-0000-4000-8000-000000000012")!
        )
        let stalePlan = try ExternalReviewImportPlanV1(
            workspaceID: workspaceID,
            requestPublicID: requestID,
            basisWorkspaceRevision: 8,
            responseRecord: responseRecord,
            c14Mapping: mapping,
            disposition: .staleLocalRevision,
            proofAssessment: proofAssessment,
            decision: .recordAsHistoryOnly,
            mutationID: mutationID
        )
        XCTAssertEqual(stalePlan.disposition, .staleLocalRevision)
        XCTAssertEqual(stalePlan.proofAssessment.proofValidity, .valid)
        XCTAssertEqual(stalePlan.proofAssessment.applicationEligibility, .stale)
        let historyReceipt = try ExternalReviewImportReceiptV1(
            workspaceID: workspaceID,
            basisWorkspaceRevision: stalePlan.basisWorkspaceRevision,
            responseRecord: responseRecord,
            decision: .recordAsHistoryOnly,
            mutationID: mutationID,
            effectDigest: Data(repeating: 0xCC, count: PortableReviewLimitsV1.digestByteCount),
            proofAssessment: stalePlan.proofAssessment,
            resultingLifecycleState: .historyOnlyTerminal,
            appliedWorkspaceRevision: nil
        )
        XCTAssertEqual(historyReceipt.decision, .recordAsHistoryOnly)
        XCTAssertEqual(historyReceipt.resultingLifecycleState, .historyOnlyTerminal)
        XCTAssertNil(historyReceipt.appliedWorkspaceRevision)

        let clonedProjection = try ReviewRequestStateProjectionV1(
            requestPublicID: requestID,
            state: .superseded,
            lifecycleState: .historyOnlyClonedOrForked,
            latestResponsePublicID: corpus.responseArchive.responsePublicID
        )
        XCTAssertEqual(clonedProjection.lifecycleState, .historyOnlyClonedOrForked)
        XCTAssertEqual(clonedProjection.state, .superseded)
        XCTAssertEqual(clonedProjection.latestResponsePublicID, corpus.responseArchive.responsePublicID)
        XCTAssertTrue(
            corpus.lifecycle.capabilityStates.contains(
                PortableReviewLifecycleStateV1.historyOnlyClonedOrForked.rawValue
            )
        )
        XCTAssertTrue(
            corpus.importFixture.dispositions.contains(
                ExternalReviewImportDispositionV1.divergentSameResponseID.rawValue
            )
        )
        try await assertC48SessionStoreBackupRestoreCloneForkEraseAndNamespaceIsolation()
    }

    func testV23P03C48R02PreparedCloneReplayRemovalInventoryAndThirdBytesFailClosed() async throws {
        let productionVector = try ReviewCapabilityProofVectorV1.rv1001()
        let secondCapability = try BearerResponseCapabilityV1(
            rawBytes: C48PortableReviewTestSupport.flipped(productionVector.capability.rawBytes)
        )

        // A PREPARED clone replay is authorized by the exact journal and
        // staged-old capability even when the canonical capability is already
        // absent and the target history-only envelope is already installed.
        let preparedRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V9_55-C48-prepared-clone-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: preparedRoot) }
        let preparedStore = try PortableExchangeSessionStoreV2(applicationSupportURL: preparedRoot)
        let preparedSessionID = UUID(uuidString: "48000000-0000-4000-8000-000000000050")!
        _ = try await preparedStore.stage(
            sessionID: preparedSessionID,
            publicRequestID: "review-request-prepared-clone",
            workspaceID: UUID(uuidString: "48000000-0000-4000-8000-000000000051")!,
            canonicalReviewIdentity: "review-prepared-clone",
            canonicalSubjectIdentity: "subject-prepared-clone",
            protocolReleaseDigest: productionVector.input.protocolReleaseDigest,
            capability: productionVector.capability
        )
        _ = try await preparedStore.markExported(id: preparedSessionID)
        let preparedSnapshot = try await preparedStore.snapshotForBackup()
        let preparedSource = try XCTUnwrap(preparedSnapshot.sessions.first)
        let preparedOperationID = UUID(uuidString: "48000000-0000-4000-8000-000000000052")!
        let preparedGenerationID = UUID(uuidString: "48000000-0000-4000-8000-000000000053")!
        let preparedBeforeSHA256 = try PortableExchangeSessionStoreV2.recoveryStateSHA256(
            applicationSupportURL: preparedRoot
        )
        let preparedTargetSession = try PortableExchangeSessionRecordV2(
            sessionID: preparedSource.sessionID,
            namespace: preparedSource.namespace,
            publicRequestID: preparedSource.publicRequestID,
            revision: preparedSource.revision,
            workspaceID: preparedSource.workspaceID,
            canonicalReviewIdentity: preparedSource.canonicalReviewIdentity,
            canonicalSubjectIdentity: preparedSource.canonicalSubjectIdentity,
            protocolReleaseDigest: preparedSource.protocolReleaseDigest,
            pendingMutationID: nil,
            pendingEffectSHA256: nil,
            pendingImportReceiptSHA256: nil,
            createdAt: preparedSource.createdAt,
            updatedAt: preparedSource.updatedAt,
            state: .historyOnlyClonedOrForked,
            capabilityState: .historyOnlyClonedOrForked,
            attemptCount: preparedSource.attemptCount,
            immutableBytes: preparedSource.immutableBytes,
            protectedCapability: nil,
            responseIDs: preparedSource.responseIDs,
            requestManifestSHA256: preparedSource.requestManifestSHA256,
            requestPackageSHA256: preparedSource.requestPackageSHA256,
            acceptedResponseSHA256: preparedSource.acceptedResponseSHA256,
            cloneOrForkGenerationID: preparedGenerationID,
            escapedCopyAcknowledged: preparedSource.escapedCopyAcknowledged
        )
        let preparedTargetEnvelope = try PortableExchangeSessionEnvelopeV2(
            generationID: preparedGenerationID,
            updatedAt: preparedSnapshot.createdAt,
            sessions: [preparedTargetSession],
            quarantine: []
        ).canonicalSorted()
        let preparedTargetData = try StoreMigrationCanonicalJSONV1.encode(preparedTargetEnvelope)
        let preparedAfterSHA256 = StoreMigrationCanonicalJSONV1.sha256(preparedTargetData)
        let preparedJournal = try PortableExchangeJournalEntryV2(
            operationID: preparedOperationID,
            operation: .restore,
            namespace: nil,
            sessionID: nil,
            beforeSHA256: preparedBeforeSHA256,
            afterSHA256: preparedAfterSHA256,
            phase: .prepared,
            createdAt: preparedSnapshot.createdAt
        )
        let preparedStoreRoot = preparedRoot.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.directoryName,
            isDirectory: true
        )
        let preparedCapabilityRoot = preparedStoreRoot.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.capabilityDirectoryName,
            isDirectory: true
        )
        let preparedCapabilityURL = preparedCapabilityRoot.appendingPathComponent(
            "\(preparedSessionID.uuidString.lowercased()).bin",
            isDirectory: false
        )
        let preparedCapabilityBytes = try Data(contentsOf: preparedCapabilityURL)
        let preparedStageURL = preparedCapabilityRoot.appendingPathComponent(
            ".recovery-old-\(preparedOperationID.uuidString.lowercased())-\(preparedSessionID.uuidString.lowercased())-\(StoreMigrationCanonicalJSONV1.sha256(preparedCapabilityBytes)).bin",
            isDirectory: false
        )
        try preparedCapabilityBytes.write(to: preparedStageURL, options: .atomic)
        try ProtectedFilePolicyV1.applyAndVerify(.portableExchangeSessionFile, at: preparedStageURL)
        try FileManager.default.removeItem(at: preparedCapabilityURL)
        let preparedEnvelopeURL = preparedStoreRoot.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.envelopeFileName,
            isDirectory: false
        )
        try preparedTargetData.write(to: preparedEnvelopeURL, options: .atomic)
        try ProtectedFilePolicyV1.applyAndVerify(.portableExchangeSessionFile, at: preparedEnvelopeURL)
        let preparedJournalURL = preparedStoreRoot.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.journalFileName,
            isDirectory: false
        )
        try StoreMigrationCanonicalJSONV1.encode(preparedJournal).write(
            to: preparedJournalURL,
            options: .atomic
        )
        try ProtectedFilePolicyV1.applyAndVerify(.portableExchangeJournalFile, at: preparedJournalURL)
        let preparedReceipt = try PortableExchangeSessionStoreV2.restoreSnapshotForRecovery(
            applicationSupportURL: preparedRoot,
            snapshot: preparedSnapshot,
            operationID: preparedOperationID,
            expectedResultGenerationID: preparedGenerationID,
            cloneOrFork: true,
            expectedBeforeEnvelopeSHA256: preparedBeforeSHA256
        )
        XCTAssertEqual(preparedReceipt.restoredSessionCount, 1)
        XCTAssertEqual(preparedReceipt.activeCapabilitiesPreserved, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preparedCapabilityURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: preparedStageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: preparedJournalURL.path))

        // Recovery plans over the union of old and target capability owners:
        // a capability belonging to an old session absent from the target is
        // removed rather than becoming an orphan.
        let removalRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V9_55-C48-capability-removal-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: removalRoot) }
        let removalStore = try PortableExchangeSessionStoreV2(applicationSupportURL: removalRoot)
        let retainedID = UUID(uuidString: "48000000-0000-4000-8000-000000000054")!
        let removedID = UUID(uuidString: "48000000-0000-4000-8000-000000000055")!
        _ = try await removalStore.stage(
            sessionID: retainedID,
            publicRequestID: "review-request-retained",
            capability: productionVector.capability
        )
        _ = try await removalStore.stage(
            sessionID: removedID,
            publicRequestID: "review-request-removed",
            capability: secondCapability
        )
        let removalSourceSnapshot = try await removalStore.snapshotForBackup()
        let removalTargetSnapshot = try PortableExchangeBackupSnapshotV2(
            snapshotID: removalSourceSnapshot.snapshotID,
            createdAt: removalSourceSnapshot.createdAt,
            sessions: removalSourceSnapshot.sessions.filter { $0.sessionID == retainedID },
            immutablePayloads: [],
            protectedCapabilityArtifacts: removalSourceSnapshot.protectedCapabilityArtifacts.filter {
                $0.sessionID == retainedID
            }
        )
        let removalBeforeSHA256 = try PortableExchangeSessionStoreV2.recoveryStateSHA256(
            applicationSupportURL: removalRoot
        )
        _ = try PortableExchangeSessionStoreV2.restoreSnapshotForRecovery(
            applicationSupportURL: removalRoot,
            snapshot: removalTargetSnapshot,
            operationID: UUID(uuidString: "48000000-0000-4000-8000-000000000056")!,
            expectedResultGenerationID: UUID(uuidString: "48000000-0000-4000-8000-000000000057")!,
            cloneOrFork: false,
            expectedBeforeEnvelopeSHA256: removalBeforeSHA256
        )
        let removalCapabilityRoot = removalRoot
            .appendingPathComponent(PortableExchangeSessionStoreLayoutV2.directoryName, isDirectory: true)
            .appendingPathComponent(PortableExchangeSessionStoreLayoutV2.capabilityDirectoryName, isDirectory: true)
        let retainedCapabilityURL = removalCapabilityRoot.appendingPathComponent(
            "\(retainedID.uuidString.lowercased()).bin"
        )
        let removedCapabilityURL = removalCapabilityRoot.appendingPathComponent(
            "\(removedID.uuidString.lowercased()).bin"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedCapabilityURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedCapabilityURL.path))
        let removalReopenedStore = try PortableExchangeSessionStoreV2(
            applicationSupportURL: removalRoot
        )
        let removedSession = try await removalReopenedStore.session(id: removedID)
        XCTAssertNil(removedSession)

        // Once the exact target exists, unrelated canonical capability files
        // and third bytes at an expected capability path both fail closed.
        let inventoryOperationID = UUID(uuidString: "48000000-0000-4000-8000-000000000058")!
        let inventoryGenerationID = UUID(uuidString: "48000000-0000-4000-8000-000000000059")!
        let inventoryBeforeSHA256 = try PortableExchangeSessionStoreV2.recoveryStateSHA256(
            applicationSupportURL: removalRoot
        )
        let inventoryReceipt = try PortableExchangeSessionStoreV2.restoreSnapshotForRecovery(
            applicationSupportURL: removalRoot,
            snapshot: removalTargetSnapshot,
            operationID: inventoryOperationID,
            expectedResultGenerationID: inventoryGenerationID,
            cloneOrFork: false,
            expectedBeforeEnvelopeSHA256: inventoryBeforeSHA256
        )
        let orphanID = UUID(uuidString: "48000000-0000-4000-8000-000000000060")!
        let orphanURL = removalCapabilityRoot.appendingPathComponent(
            "\(orphanID.uuidString.lowercased()).bin"
        )
        try Data(repeating: 0xEE, count: PortableReviewLimitsV1.capabilityByteCount).write(
            to: orphanURL,
            options: .atomic
        )
        try ProtectedFilePolicyV1.applyAndVerify(.portableExchangeSessionFile, at: orphanURL)
        XCTAssertThrowsError(
            try PortableExchangeSessionStoreV2.restoreSnapshotForRecovery(
                applicationSupportURL: removalRoot,
                snapshot: removalTargetSnapshot,
                operationID: inventoryOperationID,
                expectedResultGenerationID: inventoryGenerationID,
                cloneOrFork: false,
                expectedBeforeEnvelopeSHA256: inventoryBeforeSHA256
            )
        ) { error in
            XCTAssertEqual(error as? PortableExchangePersistenceFailureV2, .corruptStore)
        }
        try FileManager.default.removeItem(at: orphanURL)

        let exactCapabilityBytes = try Data(contentsOf: retainedCapabilityURL)
        try C48PortableReviewTestSupport.flipped(exactCapabilityBytes).write(
            to: retainedCapabilityURL,
            options: .atomic
        )
        try ProtectedFilePolicyV1.applyAndVerify(.portableExchangeSessionFile, at: retainedCapabilityURL)
        XCTAssertThrowsError(
            try PortableExchangeSessionStoreV2.restoreSnapshotForRecovery(
                applicationSupportURL: removalRoot,
                snapshot: removalTargetSnapshot,
                operationID: inventoryOperationID,
                expectedResultGenerationID: inventoryGenerationID,
                cloneOrFork: false,
                expectedBeforeEnvelopeSHA256: inventoryBeforeSHA256
            )
        ) { error in
            XCTAssertEqual(error as? PortableExchangePersistenceFailureV2, .corruptStore)
        }
        XCTAssertEqual(inventoryReceipt.restoredSessionCount, 1)
    }

    private func assertC48SessionStorePreviewApplyReplayAndDivergence() async throws {
        let corpus = try C48PortableReviewTestSupport.fixture()
        let vector = try XCTUnwrap(corpus.normativeVectors.first)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V9_55-C48-preview-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try PortableExchangeSessionStoreV2(applicationSupportURL: root)
        let sessionID = UUID(uuidString: "48000000-0000-4000-8000-000000000020")!
        let workspaceID = UUID(uuidString: "48000000-0000-4000-8000-000000000021")!
        let productionVector = try ReviewCapabilityProofVectorV1.rv1001()
        let staged = try await store.stage(PortableExchangeSessionStageInputV2(
            sessionID: sessionID,
            namespace: .review,
            publicRequestID: vector.requestPublicID,
            revision: 1,
            workspaceID: workspaceID,
            canonicalReviewIdentity: "review-identity-1",
            canonicalSubjectIdentity: "subject-identity-1",
            protocolReleaseDigest: productionVector.input.protocolReleaseDigest,
            requestManifestBytes: Data("manifest-v1".utf8),
            requestPackageBytes: Data("package-v1".utf8),
            capability: productionVector.capability,
            state: .openUnexported
        ))
        XCTAssertEqual(staged.capabilityState, .issuedNotExported)
        XCTAssertNotNil(staged.protectedCapability)
        let exported = try await store.markExported(id: sessionID)
        XCTAssertEqual(exported.state, .exportedAwaitingResponse)
        XCTAssertEqual(exported.capabilityState, .exportedAccepting)

        let author = try ResponseAuthorAssertionV1(displayName: "External reviewer")
        let acknowledgedBody = try ReviewResponseBodyV1(
            disposition: .acknowledged,
            author: author
        )
        let response = try C48PortableReviewTestSupport.response(
            vector: vector,
            staged: exported,
            responsePublicID: corpus.responseArchive.responsePublicID,
            body: acknowledgedBody
        )
        let beforeSessions = try await store.sessions(in: .review)
        let beforeStatistics = try await store.statistics(for: .review)
        let preview = try await store.previewImport(
            response,
            capability: productionVector.capability
        )
        XCTAssertEqual(preview.requestPublicID, vector.requestPublicID)
        XCTAssertEqual(preview.disposition, .exactPendingDecision)
        XCTAssertEqual(preview.proofAssessment.proofValidity, .valid)
        XCTAssertEqual(preview.proofAssessment.applicationEligibility, .eligible)
        let afterPreviewSessions = try await store.sessions(in: .review)
        let afterPreviewStatistics = try await store.statistics(for: .review)
        XCTAssertEqual(afterPreviewSessions, beforeSessions)
        XCTAssertEqual(afterPreviewStatistics, beforeStatistics)

        let invalidProof = try ReviewCapabilityProofV1(
            rawBytes: C48PortableReviewTestSupport.flipped(response.proof.rawBytes)
        )
        let invalidResponse = try C48PortableReviewTestSupport.response(
            vector: vector,
            staged: exported,
            responsePublicID: "review-response-invalid-proof",
            body: acknowledgedBody,
            proof: invalidProof
        )
        let invalidPreview = try await store.previewImport(
            invalidResponse,
            capability: productionVector.capability
        )
        XCTAssertEqual(invalidPreview.disposition, .capabilityProofInvalid)
        XCTAssertEqual(invalidPreview.proofAssessment.proofValidity, .invalid)
        let afterInvalidPreviewStatistics = try await store.statistics(for: .review)
        XCTAssertEqual(afterInvalidPreviewStatistics, beforeStatistics)

        let importReceipt = try await store.applyImport(
            response,
            decision: .acceptAndApply,
            capability: productionVector.capability,
            operationID: UUID(uuidString: "48000000-0000-4000-8000-000000000022")!
        )
        XCTAssertEqual(importReceipt.decision, .acceptAndApply)
        XCTAssertEqual(importReceipt.resultingState, .acknowledgedAwaitingDecision)
        XCTAssertEqual(importReceipt.proofAssessment.proofValidity, .valid)
        XCTAssertFalse(importReceipt.appliedToCanonicalC14)
        let acceptedOptional = try await store.session(id: sessionID)
        let accepted = try XCTUnwrap(acceptedOptional)
        XCTAssertEqual(accepted.state, .acknowledgedAwaitingDecision)
        XCTAssertEqual(accepted.capabilityState, .responsePendingDecision)
        XCTAssertNotNil(accepted.protectedCapability)
        XCTAssertEqual(accepted.responseIDs, [response.responsePublicID])

        let duplicate = try await store.previewImport(
            response,
            capability: productionVector.capability
        )
        XCTAssertEqual(duplicate.disposition, .duplicateAlreadyApplied)
        XCTAssertEqual(duplicate.proofAssessment.proofValidity, .valid)
        XCTAssertEqual(duplicate.proofAssessment.applicationEligibility, .closed)

        let approvedBody = try ReviewResponseBodyV1(
            disposition: .approved,
            author: author
        )
        let divergent = try C48PortableReviewTestSupport.response(
            vector: vector,
            staged: exported,
            responsePublicID: response.responsePublicID,
            body: approvedBody,
            proof: response.proof
        )
        let divergentPreview = try await store.previewImport(
            divergent,
            capability: productionVector.capability
        )
        XCTAssertEqual(divergentPreview.disposition, .divergentSameResponseID)
        XCTAssertEqual(divergentPreview.proofAssessment.proofValidity, .invalid)
        XCTAssertEqual(divergentPreview.proofAssessment.applicationEligibility, .closed)
        let afterDivergenceOptional = try await store.session(id: sessionID)
        let afterDivergence = try XCTUnwrap(afterDivergenceOptional)
        XCTAssertEqual(afterDivergence.responseIDs, [response.responsePublicID])
        XCTAssertEqual(afterDivergence.acceptedResponseSHA256, accepted.acceptedResponseSHA256)

        let unknownRequestID = try ReviewRequestPublicIDV1("review-request-unknown")
        let unknownResponse = try ReviewResponseEnvelopeV1(
            responsePublicID: "review-response-unknown",
            requestPublicID: unknownRequestID,
            body: acknowledgedBody,
            proof: response.proof,
            canonicalBodyDigest: productionVector.input.canonicalResponseBodyDigest
        )
        let unknownPreview = try await store.previewImport(
            unknownResponse,
            capability: productionVector.capability
        )
        XCTAssertEqual(unknownPreview.disposition, .unknownRequest)
        XCTAssertEqual(unknownPreview.proofAssessment.proofValidity, .unavailable)
        XCTAssertEqual(unknownPreview.proofAssessment.applicationEligibility, .unavailable)
    }

    private func assertC48SessionStoreBackupRestoreCloneForkEraseAndNamespaceIsolation() async throws {
        let corpus = try C48PortableReviewTestSupport.fixture()
        let vector = try XCTUnwrap(corpus.normativeVectors.first)
        let productionVector = try ReviewCapabilityProofVectorV1.rv1001()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V9_55-C48-store-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try PortableExchangeSessionStoreV2(applicationSupportURL: root)
        let reviewID = UUID(uuidString: "48000000-0000-4000-8000-000000000030")!
        let serviceID = UUID(uuidString: "48000000-0000-4000-8000-000000000031")!
        let review = try await store.stage(PortableExchangeSessionStageInputV2(
            sessionID: reviewID,
            namespace: .review,
            publicRequestID: vector.requestPublicID,
            revision: 1,
            workspaceID: UUID(uuidString: "48000000-0000-4000-8000-000000000032")!,
            canonicalReviewIdentity: "review-identity-restore",
            canonicalSubjectIdentity: "subject-identity-restore",
            protocolReleaseDigest: productionVector.input.protocolReleaseDigest,
            requestManifestBytes: Data("review-manifest".utf8),
            requestPackageBytes: Data("review-package".utf8),
            capability: productionVector.capability,
            state: .openUnexported
        ))
        _ = try await store.markExported(id: reviewID)
        let scratchService = try await store.stage(PortableExchangeSessionStageInputV2(
            sessionID: serviceID,
            namespace: .serviceRequest,
            publicRequestID: "service-request-1",
            revision: 1,
            requestManifestBytes: Data("service-manifest".utf8),
            requestPackageBytes: Data("service-package".utf8),
            state: .openUnexported
        ))
        XCTAssertEqual(review.namespace, .review)
        XCTAssertEqual(scratchService.namespace, .serviceRequest)
        let reviewLookup = try await store.session(publicRequestID: vector.requestPublicID, namespace: .review)
        let serviceLookup = try await store.session(publicRequestID: "service-request-1", namespace: .serviceRequest)
        XCTAssertEqual(reviewLookup?.sessionID, reviewID)
        XCTAssertEqual(serviceLookup?.sessionID, serviceID)
        let reviewStatistics = try await store.statistics(for: .review)
        let serviceStatistics = try await store.statistics(for: .serviceRequest)
        XCTAssertEqual(reviewStatistics.sessionCount, 1)
        XCTAssertEqual(serviceStatistics.sessionCount, 1)
        XCTAssertEqual(
            C48PortableReviewNamespaceQuotaCatalogV2.quota(for: .review).maximumSessions,
            C48PortableReviewNamespaceQuotaCatalogV2.quota(for: .serviceRequest).maximumSessions
        )

        do {
            _ = try await store.deleteUnfinalizedSubject(
                sessionID: serviceID,
                tombstoneProven: false,
                operationID: UUID(uuidString: "48000000-0000-4000-8000-000000000036")!
            )
            XCTFail("untombstoned service-request cleanup must fail closed")
        } catch let error as PortableExchangePersistenceFailureV2 {
            XCTAssertEqual(error, .invalidTransition)
        }
        XCTAssertTrue(
            try await store.deleteUnfinalizedSubject(
                sessionID: serviceID,
                tombstoneProven: true,
                operationID: UUID(uuidString: "48000000-0000-4000-8000-000000000037")!
            )
        )
        let service = try await store.stage(PortableExchangeSessionStageInputV2(
            sessionID: serviceID,
            namespace: .serviceRequest,
            publicRequestID: "service-request-1",
            revision: 1,
            state: .closedWithoutResponse
        ))
        XCTAssertEqual(service.state, .closedWithoutResponse)

        let snapshot = try await store.snapshotForBackup()
        XCTAssertEqual(snapshot.sessions.count, 2)
        XCTAssertEqual(snapshot.immutablePayloads.count, 2)
        XCTAssertEqual(snapshot.protectedCapabilityArtifacts.count, 1)
        XCTAssertTrue(snapshot.sessions.allSatisfy { $0.state != .quarantined && $0.state != .erased })
        XCTAssertTrue(C48PortableReviewPersistenceBoundaryV1.sessionStoreIsNonpersistent)
        XCTAssertTrue(C48PortableReviewPersistenceBoundaryV1.quarantineIsExcludedFromBackup)
        XCTAssertTrue(C48PortableReviewPersistenceBoundaryV1.reviewAndServiceNamespacesAreIndependent)

        let recoveryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V9_55-C48-static-recovery-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: recoveryRoot) }
        let recoveryOperationID = UUID(uuidString: "48000000-0000-4000-8000-000000000042")!
        let recoveryGenerationID = UUID(uuidString: "48000000-0000-4000-8000-000000000043")!
        let emptyEnvelopeSHA256 = StoreMigrationCanonicalJSONV1.sha256(Data())
        let firstRecoveryReceipt = try PortableExchangeSessionStoreV2.restoreSnapshotForRecovery(
            applicationSupportURL: recoveryRoot,
            snapshot: snapshot,
            operationID: recoveryOperationID,
            expectedResultGenerationID: recoveryGenerationID,
            cloneOrFork: false,
            expectedBeforeEnvelopeSHA256: emptyEnvelopeSHA256
        )
        let firstRecoveryEffect = try PortableExchangeSessionStoreV2.recoveryStateSHA256(
            applicationSupportURL: recoveryRoot
        )
        let repeatedRecoveryReceipt = try PortableExchangeSessionStoreV2.restoreSnapshotForRecovery(
            applicationSupportURL: recoveryRoot,
            snapshot: snapshot,
            operationID: recoveryOperationID,
            expectedResultGenerationID: recoveryGenerationID,
            cloneOrFork: false,
            expectedBeforeEnvelopeSHA256: emptyEnvelopeSHA256
        )
        XCTAssertEqual(repeatedRecoveryReceipt, firstRecoveryReceipt)
        XCTAssertEqual(
            try PortableExchangeSessionStoreV2.recoveryStateSHA256(
                applicationSupportURL: recoveryRoot
            ),
            firstRecoveryEffect
        )
        XCTAssertThrowsError(
            try PortableExchangeSessionStoreV2.restoreSnapshotForRecovery(
                applicationSupportURL: recoveryRoot,
                snapshot: snapshot,
                operationID: recoveryOperationID,
                expectedResultGenerationID: UUID(uuidString: "48000000-0000-4000-8000-000000000044")!,
                cloneOrFork: false,
                expectedBeforeEnvelopeSHA256: emptyEnvelopeSHA256
            )
        ) { error in
            XCTAssertEqual(error as? PortableExchangePersistenceFailureV2, .corruptStore)
        }

        let cloneRecoveryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V9_55-C48-static-clone-recovery-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: cloneRecoveryRoot) }
        _ = try PortableExchangeSessionStoreV2.restoreSnapshotForRecovery(
            applicationSupportURL: cloneRecoveryRoot,
            snapshot: snapshot,
            operationID: UUID(uuidString: "48000000-0000-4000-8000-000000000045")!,
            expectedResultGenerationID: UUID(uuidString: "48000000-0000-4000-8000-000000000046")!,
            cloneOrFork: true,
            expectedBeforeEnvelopeSHA256: emptyEnvelopeSHA256
        )
        let cloneRecoveryStore = try PortableExchangeSessionStoreV2(
            applicationSupportURL: cloneRecoveryRoot
        )
        let cloneRecoveredReviewOptional = try await cloneRecoveryStore.session(id: reviewID)
        let cloneRecoveredReview = try XCTUnwrap(cloneRecoveredReviewOptional)
        XCTAssertEqual(cloneRecoveredReview.state, .historyOnlyClonedOrForked)
        XCTAssertEqual(cloneRecoveredReview.capabilityState, .historyOnlyClonedOrForked)
        XCTAssertNil(cloneRecoveredReview.protectedCapability)

        let restore = try await store.replaceRestore(
            with: snapshot,
            operationID: UUID(uuidString: "48000000-0000-4000-8000-000000000033")!
        )
        XCTAssertEqual(restore.restoredSessionCount, 2)
        XCTAssertEqual(restore.activeCapabilitiesPreserved, 1)
        XCTAssertTrue(restore.quarantineExcluded)
        XCTAssertTrue(restore.idempotent)
        let restoredReviewOptional = try await store.session(id: reviewID)
        let restoredReview = try XCTUnwrap(restoredReviewOptional)
        XCTAssertEqual(restoredReview.protectedCapability?.byteCount, 32)
        XCTAssertEqual(restoredReview.capabilityState, .exportedAccepting)

        let clone = try await store.markClonedOrForked(
            operationID: UUID(uuidString: "48000000-0000-4000-8000-000000000034")!,
            resultGenerationID: UUID(uuidString: "48000000-0000-4000-8000-000000000035")!
        )
        XCTAssertEqual(clone.invalidatedSessionCount, 1)
        XCTAssertEqual(clone.preservedHistoryCount, 2)
        XCTAssertTrue(clone.activeCapabilitiesInvalidated)
        let clonedReviewOptional = try await store.session(id: reviewID)
        let clonedReview = try XCTUnwrap(clonedReviewOptional)
        XCTAssertEqual(clonedReview.state, .historyOnlyClonedOrForked)
        XCTAssertEqual(clonedReview.capabilityState, .historyOnlyClonedOrForked)
        XCTAssertNil(clonedReview.protectedCapability)
        let serviceStatisticsAfterClone = try await store.statistics(for: .serviceRequest)
        XCTAssertEqual(serviceStatisticsAfterClone.sessionCount, 1)

        _ = try await store.replaceRestore(
            with: snapshot,
            operationID: UUID(uuidString: "48000000-0000-4000-8000-000000000038")!
        )

        let erase = try await store.erase(
            operationID: UUID(uuidString: "48000000-0000-4000-8000-000000000039")!
        )
        XCTAssertEqual(erase.erasedSessionCount, 2)
        XCTAssertEqual(erase.erasedCapabilityCount, 1)
        XCTAssertEqual(erase.erasedQuarantineCount, 0)
        XCTAssertEqual(erase.escapedCopiesAcknowledged, 0)
        XCTAssertGreaterThan(erase.appOwnedBytesRemoved, 0)
        let sessionsAfterErase = try await store.sessions(in: nil)
        let reviewStatisticsAfterErase = try await store.statistics(for: .review)
        let serviceStatisticsAfterErase = try await store.statistics(for: .serviceRequest)
        XCTAssertTrue(sessionsAfterErase.isEmpty)
        XCTAssertEqual(reviewStatisticsAfterErase.sessionCount, 0)
        XCTAssertEqual(serviceStatisticsAfterErase.sessionCount, 0)

        XCTAssertThrowsError(
            try PortableExchangeImmutableByteReferenceV2(
                role: .requestPackage,
                sha256: String(repeating: "a", count: 64),
                byteCount: 1,
                relativePath: "../escape",
                released: true
            )
        ) { error in
            XCTAssertEqual(error as? PortableExchangePersistenceFailureV2, .invalidRecord)
        }
        XCTAssertThrowsError(
            try PortableExchangeProtectedCapabilityArtifactV2(
                relativePath: "payload/not-a-capability.bin",
                byteCount: 32,
                sha256: String(repeating: "a", count: 64),
                state: .exportedAccepting
            )
        ) { error in
            XCTAssertEqual(error as? PortableExchangePersistenceFailureV2, .invalidCapabilityArtifact)
        }
        let quarantined = try PortableExchangeSessionRecordV2(
            sessionID: UUID(uuidString: "48000000-0000-4000-8000-000000000040")!,
            namespace: .review,
            publicRequestID: "quarantined-session",
            revision: 1,
            createdAt: C48PortableReviewTestSupport.fixedDate,
            updatedAt: C48PortableReviewTestSupport.fixedDate,
            state: .quarantined,
            capabilityState: .unavailableCorruptOrMissing
        )
        XCTAssertThrowsError(
            try PortableExchangeBackupSnapshotV2(
                createdAt: C48PortableReviewTestSupport.fixedDate,
                sessions: [quarantined]
            )
        ) { error in
            XCTAssertEqual(error as? PortableExchangePersistenceFailureV2, .invalidBackupSnapshot)
        }
        XCTAssertThrowsError(
            try PortableExchangeSessionEnvelopeV2(
                generationID: UUID(uuidString: "48000000-0000-4000-8000-000000000041")!,
                updatedAt: C48PortableReviewTestSupport.fixedDate,
                sessions: [quarantined, quarantined]
            )
        ) { error in
            XCTAssertEqual(error as? PortableExchangePersistenceFailureV2, .invalidEnvelope)
        }
    }
}
private final class C49PortableReviewRegressionBoundaryTests: XCTestCase {
    func testC49DoesNotChangeC48CapabilityOrExchangeAuthority() {
        XCTAssertTrue(C49WorkResourceContractBoundaryV1.appendOnly)
        XCTAssertEqual(C49WorkResourceContractBoundaryV1.soleWriter, "WorkspaceWriterV1")
    }
}

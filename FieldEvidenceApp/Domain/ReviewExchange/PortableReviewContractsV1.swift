import CryptoKit
import Foundation
import Security

// Clear portable-review contracts deliberately prove possession of the request
// capability only. They do not establish a person's identity, authority,
// delivery, review, legal effect, or security of a shared cleartext file.

enum PortableReviewFailureV1: Error, Equatable, Sendable {
    case invalidIdentity
    case invalidValue
    case invalidDigest
    case invalidCapability
    case invalidProof
    case nonCanonicalEncoding
    case unsupportedProtocol
    case malformedTranscript
    case proofMismatch
    case ineligibleApplication
    case conflictingResponse
}

enum PortableReviewLimitsV1 {
    static let digestByteCount = 32
    static let capabilityByteCount = 32
    static let proofByteCount = 32
    static let maximumAuthorBytes = 160
    static let maximumResponseBytes = 64 * 1_024
    static let maximumChangeItems = 64
    static let maximumExchangeSessions = 512

    static func rawDigest(_ value: Data) throws {
        guard value.count == digestByteCount else { throw PortableReviewFailureV1.invalidDigest }
    }

    static func capability(_ value: Data) throws {
        guard value.count == capabilityByteCount else { throw PortableReviewFailureV1.invalidCapability }
    }

    static func proof(_ value: Data) throws {
        guard value.count == proofByteCount else { throw PortableReviewFailureV1.invalidProof }
    }

    static func canonicalASCII(_ value: String) throws {
        guard !value.isEmpty, !value.utf8.contains(0), value.unicodeScalars.allSatisfy({ $0.value <= 0x7f }),
              value.data(using: .ascii)?.count == value.utf8.count else {
            throw PortableReviewFailureV1.nonCanonicalEncoding
        }
    }

    static func boundedText(_ value: String, maximumBytes: Int) throws {
        guard !value.isEmpty, value.utf8.count <= maximumBytes,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw PortableReviewFailureV1.invalidValue
        }
    }
}

/// A released public request identifier. The caller must supply already-released
/// canonical ASCII bytes; this type intentionally does not normalize or rewrite it.
struct ReviewRequestPublicIDV1: Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) throws {
        self.rawValue = rawValue
        try validate()
    }

    func validate() throws { try PortableReviewLimitsV1.canonicalASCII(rawValue) }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(try container.decode(String.self))
    }
}

struct BearerResponseCapabilityV1: Equatable, Hashable, Sendable {
    let rawBytes: Data

    init(rawBytes: Data) throws {
        self.rawBytes = rawBytes
        try PortableReviewLimitsV1.capability(rawBytes)
    }

    static func issue() throws -> BearerResponseCapabilityV1 {
        var bytes = Data(repeating: 0, count: PortableReviewLimitsV1.capabilityByteCount)
        let status = bytes.withUnsafeMutableBytes { destination in
            guard let address = destination.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, PortableReviewLimitsV1.capabilityByteCount, address)
        }
        guard status == errSecSuccess else { throw PortableReviewFailureV1.invalidCapability }
        return try BearerResponseCapabilityV1(rawBytes: bytes)
    }
}

struct ReviewCapabilityProofV1: Codable, Equatable, Hashable, Sendable {
    let rawBytes: Data

    init(rawBytes: Data) throws {
        self.rawBytes = rawBytes
        try PortableReviewLimitsV1.proof(rawBytes)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawBytes: container.decode(Data.self))
    }
}

struct ReviewCapabilityProofInputV1: Equatable, Sendable {
    let protocolReleaseDigest: Data
    let requestPublicID: ReviewRequestPublicIDV1
    let requestManifestDigest: Data
    let innerRequestPackageDigest: Data
    let canonicalResponseBodyDigest: Data

    init(protocolReleaseDigest: Data, requestPublicID: ReviewRequestPublicIDV1,
         requestManifestDigest: Data, innerRequestPackageDigest: Data,
         canonicalResponseBodyDigest: Data) throws {
        self.protocolReleaseDigest = protocolReleaseDigest
        self.requestPublicID = requestPublicID
        self.requestManifestDigest = requestManifestDigest
        self.innerRequestPackageDigest = innerRequestPackageDigest
        self.canonicalResponseBodyDigest = canonicalResponseBodyDigest
        try validate()
    }

    func validate() throws {
        try PortableReviewLimitsV1.rawDigest(protocolReleaseDigest)
        try requestPublicID.validate()
        try PortableReviewLimitsV1.rawDigest(requestManifestDigest)
        try PortableReviewLimitsV1.rawDigest(innerRequestPackageDigest)
        try PortableReviewLimitsV1.rawDigest(canonicalResponseBodyDigest)
    }
}

enum ReviewCapabilityProofCodecV1 {
    static let domain = "AssetRounds.ReviewCapabilityProof.V1"

    static func transcript(for input: ReviewCapabilityProofInputV1) throws -> Data {
        try input.validate()
        guard let domainBytes = domain.data(using: .ascii),
              let identifierBytes = input.requestPublicID.rawValue.data(using: .ascii) else {
            throw PortableReviewFailureV1.nonCanonicalEncoding
        }
        var result = Data()
        result.append(domainBytes)
        result.append(0)
        try appendLengthPrefixed(input.protocolReleaseDigest, to: &result)
        try appendLengthPrefixed(identifierBytes, to: &result)
        try appendLengthPrefixed(input.requestManifestDigest, to: &result)
        try appendLengthPrefixed(input.innerRequestPackageDigest, to: &result)
        try appendLengthPrefixed(input.canonicalResponseBodyDigest, to: &result)
        return result
    }

    static func makeProof(capability: BearerResponseCapabilityV1,
                          input: ReviewCapabilityProofInputV1) throws -> ReviewCapabilityProofV1 {
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: try transcript(for: input), using: SymmetricKey(data: capability.rawBytes)
        )
        return try ReviewCapabilityProofV1(rawBytes: Data(authenticationCode))
    }

    static func verify(_ proof: ReviewCapabilityProofV1, capability: BearerResponseCapabilityV1,
                       input: ReviewCapabilityProofInputV1) throws -> Bool {
        let expected = try makeProof(capability: capability, input: input)
        return constantTimeEqual(expected.rawBytes, proof.rawBytes)
    }

    /// Runs over both complete 32-byte values without early exit.
    static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == PortableReviewLimitsV1.proofByteCount,
              rhs.count == PortableReviewLimitsV1.proofByteCount else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
        return difference == 0
    }

    private static func appendLengthPrefixed(_ value: Data, to result: inout Data) throws {
        guard value.count <= Int(UInt32.max) else { throw PortableReviewFailureV1.malformedTranscript }
        var length = UInt32(value.count).bigEndian
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        result.append(value)
    }
}

enum ReviewCapabilityProofVectorV1 {
    static let rv1001TranscriptSHA256Hex = "5ab5c377885c524b13b17985b5782c34937ada353916c7861a7da97a23c0f0e6"
    static let rv1001HMACSHA256Hex = "fb0b14df9c1bdbf6f19222ab40954b07a5c847eca3c5095a3cc379ff6fa5501d"
    static let rv1001TranscriptByteCount = 236

    static func rv1001() throws -> (capability: BearerResponseCapabilityV1,
                                    input: ReviewCapabilityProofInputV1,
                                    proof: ReviewCapabilityProofV1) {
        let capability = try BearerResponseCapabilityV1(rawBytes: Data(0x00...0x1f))
        let input = try ReviewCapabilityProofInputV1(
            protocolReleaseDigest: Data(0x20...0x3f),
            requestPublicID: try ReviewRequestPublicIDV1("review-request-00000000-0000-0000-0000-000000000001"),
            requestManifestDigest: Data(0x40...0x5f),
            innerRequestPackageDigest: Data(0x60...0x7f),
            canonicalResponseBodyDigest: Data(0x80...0x9f)
        )
        return (capability, input, try ReviewCapabilityProofV1(rawBytes: hex(rv1001HMACSHA256Hex)))
    }

    static func validatesRV1001() throws -> Bool {
        let vector = try rv1001()
        let transcript = try ReviewCapabilityProofCodecV1.transcript(for: vector.input)
        guard transcript.count == rv1001TranscriptByteCount,
              hexString(SHA256.hash(data: transcript)) == rv1001TranscriptSHA256Hex else { return false }
        return try ReviewCapabilityProofCodecV1.verify(vector.proof, capability: vector.capability, input: vector.input)
    }

    private static func hex(_ value: String) -> Data {
        Data(stride(from: 0, to: value.count, by: 2).map {
            UInt8(value[value.index(value.startIndex, offsetBy: $0)..<value.index(value.startIndex, offsetBy: $0 + 2)], radix: 16)!
        })
    }

    private static func hexString(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum ReviewResponseDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case acknowledged = "ACKNOWLEDGED"
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
}

struct PortableReviewProtocolReleaseV1: Codable, Equatable, Hashable, Sendable {
    static let currentProofProfile = "REVIEW_CAPABILITY_PROOF_FRAMED_V1"
    let releaseID: String
    let releaseDigest: Data
    let proofProfile: String

    init(releaseID: String, releaseDigest: Data,
         proofProfile: String = PortableReviewProtocolReleaseV1.currentProofProfile) throws {
        self.releaseID = releaseID; self.releaseDigest = releaseDigest; self.proofProfile = proofProfile
        try PortableReviewLimitsV1.canonicalASCII(releaseID)
        try PortableReviewLimitsV1.rawDigest(releaseDigest)
        guard proofProfile == Self.currentProofProfile else { throw PortableReviewFailureV1.unsupportedProtocol }
    }

    private enum CodingKeys: String, CodingKey { case releaseID, releaseDigest, proofProfile }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(releaseID: c.decode(String.self, forKey: .releaseID),
                      releaseDigest: c.decode(Data.self, forKey: .releaseDigest),
                      proofProfile: c.decode(String.self, forKey: .proofProfile))
    }
}

struct ReviewRequestManifestV1: Codable, Equatable, Hashable, Sendable {
    let requestPublicID: ReviewRequestPublicIDV1
    let protocolRelease: PortableReviewProtocolReleaseV1
    let requestManifestDigest: Data
    let innerRequestPackageDigest: Data

    init(requestPublicID: ReviewRequestPublicIDV1, protocolRelease: PortableReviewProtocolReleaseV1,
         requestManifestDigest: Data, innerRequestPackageDigest: Data) throws {
        self.requestPublicID = requestPublicID; self.protocolRelease = protocolRelease
        self.requestManifestDigest = requestManifestDigest; self.innerRequestPackageDigest = innerRequestPackageDigest
        try validate()
    }

    func validate() throws {
        try requestPublicID.validate()
        try PortableReviewLimitsV1.canonicalASCII(protocolRelease.releaseID)
        try PortableReviewLimitsV1.rawDigest(protocolRelease.releaseDigest)
        try PortableReviewLimitsV1.rawDigest(requestManifestDigest)
        try PortableReviewLimitsV1.rawDigest(innerRequestPackageDigest)
    }

    private enum CodingKeys: String, CodingKey { case requestPublicID, protocolRelease, requestManifestDigest, innerRequestPackageDigest }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(requestPublicID: c.decode(ReviewRequestPublicIDV1.self, forKey: .requestPublicID),
                      protocolRelease: c.decode(PortableReviewProtocolReleaseV1.self, forKey: .protocolRelease),
                      requestManifestDigest: c.decode(Data.self, forKey: .requestManifestDigest),
                      innerRequestPackageDigest: c.decode(Data.self, forKey: .innerRequestPackageDigest))
    }

    func proofInput(canonicalResponseBodyDigest: Data) throws -> ReviewCapabilityProofInputV1 {
        try ReviewCapabilityProofInputV1(
            protocolReleaseDigest: protocolRelease.releaseDigest,
            requestPublicID: requestPublicID,
            requestManifestDigest: requestManifestDigest,
            innerRequestPackageDigest: innerRequestPackageDigest,
            canonicalResponseBodyDigest: canonicalResponseBodyDigest
        )
    }
}

enum ReviewRequestFileEntryV1: String, Codable, CaseIterable, Hashable, Sendable {
    case manifest = "manifest.json"
    case request = "review-request.json"
    case responseCapability = "response-capability.bin"
    case reportPDF = "report/report.pdf"
    case reportText = "report/report.txt"
}

enum ResponseAuthorAssertionSourceV1: String, Codable, CaseIterable, Hashable, Sendable {
    case selfEnteredInResponder = "SELF_ENTERED_IN_RESPONDER"
    case originUserAssertionUnverified = "ORIGIN_USER_ASSERTION_UNVERIFIED"
}

struct ResponseAuthorAssertionV1: Codable, Equatable, Hashable, Sendable {
    let displayName: String
    let organization: String?
    let source: ResponseAuthorAssertionSourceV1
    let statedResponseAt: Date?
    let statedTimeZoneIdentifier: String?

    init(displayName: String, organization: String? = nil,
         source: ResponseAuthorAssertionSourceV1 = .selfEnteredInResponder,
         statedResponseAt: Date? = nil, statedTimeZoneIdentifier: String? = nil) throws {
        self.displayName = displayName; self.organization = organization; self.source = source
        self.statedResponseAt = statedResponseAt; self.statedTimeZoneIdentifier = statedTimeZoneIdentifier
        try validate()
    }

    func validate() throws {
        try PortableReviewLimitsV1.boundedText(displayName, maximumBytes: PortableReviewLimitsV1.maximumAuthorBytes)
        if let organization { try PortableReviewLimitsV1.boundedText(organization, maximumBytes: PortableReviewLimitsV1.maximumAuthorBytes) }
        if let statedResponseAt, !statedResponseAt.timeIntervalSinceReferenceDate.isFinite { throw PortableReviewFailureV1.invalidValue }
        if let statedTimeZoneIdentifier, TimeZone(identifier: statedTimeZoneIdentifier) == nil { throw PortableReviewFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey { case displayName, organization, source, statedResponseAt, statedTimeZoneIdentifier }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(displayName: c.decode(String.self, forKey: .displayName),
                      organization: c.decodeIfPresent(String.self, forKey: .organization),
                      source: c.decode(ResponseAuthorAssertionSourceV1.self, forKey: .source),
                      statedResponseAt: c.decodeIfPresent(Date.self, forKey: .statedResponseAt),
                      statedTimeZoneIdentifier: c.decodeIfPresent(String.self, forKey: .statedTimeZoneIdentifier))
    }
}

struct ReviewResponseBodyV1: Codable, Equatable, Hashable, Sendable {
    let disposition: ReviewResponseDispositionV1
    let changeItems: [String]
    let author: ResponseAuthorAssertionV1

    init(disposition: ReviewResponseDispositionV1, changeItems: [String] = [], author: ResponseAuthorAssertionV1) throws {
        self.disposition = disposition; self.changeItems = changeItems; self.author = author
        try validate()
    }

    func validate() throws {
        try author.validate()
        guard changeItems.count <= PortableReviewLimitsV1.maximumChangeItems else { throw PortableReviewFailureV1.invalidValue }
        for item in changeItems { try PortableReviewLimitsV1.boundedText(item, maximumBytes: PortableReviewLimitsV1.maximumResponseBytes) }
        switch disposition {
        case .approved: guard changeItems.isEmpty else { throw PortableReviewFailureV1.invalidValue }
        case .changesRequested: guard !changeItems.isEmpty else { throw PortableReviewFailureV1.invalidValue }
        case .acknowledged: break
        }
    }

    private enum CodingKeys: String, CodingKey { case disposition, changeItems, author }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(disposition: c.decode(ReviewResponseDispositionV1.self, forKey: .disposition),
                      changeItems: c.decode([String].self, forKey: .changeItems),
                      author: c.decode(ResponseAuthorAssertionV1.self, forKey: .author))
    }
}

struct ReviewResponseEnvelopeV1: Codable, Equatable, Hashable, Sendable {
    let responsePublicID: String
    let requestPublicID: ReviewRequestPublicIDV1
    let body: ReviewResponseBodyV1
    let proof: ReviewCapabilityProofV1
    let canonicalBodyDigest: Data

    init(responsePublicID: String, requestPublicID: ReviewRequestPublicIDV1,
         body: ReviewResponseBodyV1, proof: ReviewCapabilityProofV1, canonicalBodyDigest: Data) throws {
        self.responsePublicID = responsePublicID; self.requestPublicID = requestPublicID
        self.body = body; self.proof = proof; self.canonicalBodyDigest = canonicalBodyDigest
        try validate()
    }

    func validate() throws {
        try PortableReviewLimitsV1.canonicalASCII(responsePublicID)
        try requestPublicID.validate(); try body.validate(); try PortableReviewLimitsV1.proof(proof.rawBytes)
        try PortableReviewLimitsV1.rawDigest(canonicalBodyDigest)
    }

    private enum CodingKeys: String, CodingKey { case responsePublicID, requestPublicID, body, proof, canonicalBodyDigest }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(responsePublicID: c.decode(String.self, forKey: .responsePublicID),
                      requestPublicID: c.decode(ReviewRequestPublicIDV1.self, forKey: .requestPublicID),
                      body: c.decode(ReviewResponseBodyV1.self, forKey: .body),
                      proof: c.decode(ReviewCapabilityProofV1.self, forKey: .proof),
                      canonicalBodyDigest: c.decode(Data.self, forKey: .canonicalBodyDigest))
    }
}

enum ReviewResponseAcquisitionKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case portableFile = "PORTABLE_FILE"
    case originRecordedElsewhere = "ORIGIN_RECORDED_ELSEWHERE"
}

struct OriginRecordedReviewResponseV1: Codable, Equatable, Hashable, Sendable {
    let requestPublicID: ReviewRequestPublicIDV1
    let responseBody: ReviewResponseBodyV1
    let sourceWording: String
    let recordedByActorID: UUID
    let recordedAt: Date
    let acquisitionKind: ReviewResponseAcquisitionKindV1

    init(requestPublicID: ReviewRequestPublicIDV1, responseBody: ReviewResponseBodyV1,
         sourceWording: String, recordedByActorID: UUID, recordedAt: Date,
         acquisitionKind: ReviewResponseAcquisitionKindV1 = .originRecordedElsewhere) throws {
        self.requestPublicID = requestPublicID; self.responseBody = responseBody; self.sourceWording = sourceWording
        self.recordedByActorID = recordedByActorID; self.recordedAt = recordedAt; self.acquisitionKind = acquisitionKind
        try validate()
    }

    func validate() throws {
        try requestPublicID.validate(); try responseBody.validate()
        try PortableReviewLimitsV1.boundedText(sourceWording, maximumBytes: PortableReviewLimitsV1.maximumResponseBytes)
        guard recordedByActorID.uuidString != "00000000-0000-0000-0000-000000000000",
              recordedAt.timeIntervalSinceReferenceDate.isFinite,
              acquisitionKind == .originRecordedElsewhere,
              responseBody.author.source == .originUserAssertionUnverified else { throw PortableReviewFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey { case requestPublicID, responseBody, sourceWording, recordedByActorID, recordedAt, acquisitionKind }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(requestPublicID: c.decode(ReviewRequestPublicIDV1.self, forKey: .requestPublicID),
                      responseBody: c.decode(ReviewResponseBodyV1.self, forKey: .responseBody),
                      sourceWording: c.decode(String.self, forKey: .sourceWording),
                      recordedByActorID: c.decode(UUID.self, forKey: .recordedByActorID),
                      recordedAt: c.decode(Date.self, forKey: .recordedAt),
                      acquisitionKind: c.decode(ReviewResponseAcquisitionKindV1.self, forKey: .acquisitionKind))
    }
}

enum PortableReviewCanonicalCodecV1 {
    static func responseBytes(_ response: ReviewResponseEnvelopeV1) throws -> Data {
        try response.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(response)
    }

    static func decodeCanonicalResponse(_ bytes: Data) throws -> ReviewResponseEnvelopeV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let response = try decoder.decode(ReviewResponseEnvelopeV1.self, from: bytes)
        guard try responseBytes(response) == bytes else { throw PortableReviewFailureV1.nonCanonicalEncoding }
        return response
    }

    static func responseRecordBytes(_ payload: CanonicalReviewResponsePayloadV1) throws -> Data {
        try payload.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(payload)
    }

    static func decodeCanonicalResponseRecord(_ bytes: Data) throws -> CanonicalReviewResponsePayloadV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let payload = try decoder.decode(CanonicalReviewResponsePayloadV1.self, from: bytes)
        guard try responseRecordBytes(payload) == bytes else { throw PortableReviewFailureV1.nonCanonicalEncoding }
        return payload
    }
}

enum CanonicalReviewResponsePayloadV1: Codable, Equatable, Hashable, Sendable {
    case portable(ReviewResponseEnvelopeV1)
    case originRecorded(OriginRecordedReviewResponseV1)

    func validate() throws {
        switch self {
        case let .portable(response): try response.validate()
        case let .originRecorded(response): try response.validate()
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, portableResponse, originRecordedResponse }
    private enum Kind: String, Codable { case portable = "PORTABLE", originRecorded = "ORIGIN_RECORDED" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .portable:
            self = .portable(try c.decode(ReviewResponseEnvelopeV1.self, forKey: .portableResponse))
        case .originRecorded:
            self = .originRecorded(try c.decode(OriginRecordedReviewResponseV1.self, forKey: .originRecordedResponse))
        }
        try validate()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .portable(response):
            try c.encode(Kind.portable, forKey: .kind); try c.encode(response, forKey: .portableResponse)
        case let .originRecorded(response):
            try c.encode(Kind.originRecorded, forKey: .kind); try c.encode(response, forKey: .originRecordedResponse)
        }
    }
}

/// Immutable canonical portable-response evidence. Exact source bytes are retained
/// and only accepted when decoding and a canonical re-encode produce the same bytes.
struct CanonicalReviewResponseBytesV1: Codable, Equatable, Hashable, Sendable {
    let canonicalBytes: Data
    let byteCount: Int
    let sha256: Data

    init(canonicalBytes: Data) throws {
        let payload = try PortableReviewCanonicalCodecV1.decodeCanonicalResponseRecord(canonicalBytes)
        self.canonicalBytes = canonicalBytes
        byteCount = canonicalBytes.count
        sha256 = Data(SHA256.hash(data: canonicalBytes))
        guard byteCount > 0, try PortableReviewCanonicalCodecV1.responseRecordBytes(payload) == canonicalBytes else {
            throw PortableReviewFailureV1.nonCanonicalEncoding
        }
    }

    init(response: ReviewResponseEnvelopeV1) throws {
        try self.init(canonicalBytes: try PortableReviewCanonicalCodecV1.responseRecordBytes(.portable(response)))
    }

    init(originRecorded response: OriginRecordedReviewResponseV1) throws {
        try self.init(canonicalBytes: try PortableReviewCanonicalCodecV1.responseRecordBytes(.originRecorded(response)))
    }

    func validate() throws {
        guard byteCount == canonicalBytes.count, sha256 == Data(SHA256.hash(data: canonicalBytes)) else {
            throw PortableReviewFailureV1.invalidDigest
        }
        _ = try PortableReviewCanonicalCodecV1.decodeCanonicalResponseRecord(canonicalBytes)
    }

    private enum CodingKeys: String, CodingKey { case canonicalBytes, byteCount, sha256 }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let bytes = try c.decode(Data.self, forKey: .canonicalBytes)
        try self.init(canonicalBytes: bytes)
        guard byteCount == c.decode(Int.self, forKey: .byteCount), sha256 == c.decode(Data.self, forKey: .sha256) else {
            throw PortableReviewFailureV1.invalidDigest
        }
    }
}

enum ExternalReviewResponseSourceV1: Codable, Equatable, Hashable, Sendable {
    case portableFile
    case originRecordedElsewhere(OriginRecordedReviewResponseV1)

    private enum CodingKeys: String, CodingKey { case kind, originRecordedResponse }
    private enum Kind: String, Codable { case portableFile = "PORTABLE_FILE", originRecordedElsewhere = "ORIGIN_RECORDED_ELSEWHERE" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .portableFile: self = .portableFile
        case .originRecordedElsewhere: self = .originRecordedElsewhere(try c.decode(OriginRecordedReviewResponseV1.self, forKey: .originRecordedResponse))
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .portableFile: try c.encode(Kind.portableFile, forKey: .kind)
        case let .originRecordedElsewhere(response):
            try c.encode(Kind.originRecordedElsewhere, forKey: .kind)
            try c.encode(response, forKey: .originRecordedResponse)
        }
    }
}

struct ExternalReviewResponseRecordV1: Codable, Equatable, Hashable, Sendable {
    let recordID: UUID
    let workspaceID: WorkspaceID
    let requestManifest: ReviewRequestManifestV1
    let canonicalResponse: CanonicalReviewResponseBytesV1
    let source: ExternalReviewResponseSourceV1
    let proofAssessment: ReviewProofAssessmentV1
    let recordedAt: Date

    init(recordID: UUID, workspaceID: WorkspaceID, requestManifest: ReviewRequestManifestV1,
         canonicalResponse: CanonicalReviewResponseBytesV1, source: ExternalReviewResponseSourceV1,
         proofAssessment: ReviewProofAssessmentV1, recordedAt: Date) throws {
        self.recordID = recordID; self.workspaceID = workspaceID; self.requestManifest = requestManifest
        self.canonicalResponse = canonicalResponse; self.source = source; self.proofAssessment = proofAssessment
        self.recordedAt = recordedAt
        try validate()
    }

    func validate() throws {
        guard recordID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              workspaceID.rawValue != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              recordedAt.timeIntervalSinceReferenceDate.isFinite else { throw PortableReviewFailureV1.invalidIdentity }
        try requestManifest.validate(); try canonicalResponse.validate()
        switch source {
        case .portableFile:
            guard proofAssessment.proofValidity != .unavailable,
                  case .portable = try PortableReviewCanonicalCodecV1.decodeCanonicalResponseRecord(canonicalResponse.canonicalBytes) else {
                throw PortableReviewFailureV1.invalidValue
            }
        case let .originRecordedElsewhere(origin):
            try origin.validate()
            guard origin.requestPublicID == requestManifest.requestPublicID,
                  proofAssessment.proofValidity == .unavailable,
                  case .originRecorded(let canonicalOrigin) = try PortableReviewCanonicalCodecV1.decodeCanonicalResponseRecord(canonicalResponse.canonicalBytes),
                  canonicalOrigin == origin else { throw PortableReviewFailureV1.invalidValue }
        }
    }

    private enum CodingKeys: String, CodingKey { case recordID, workspaceID, requestManifest, canonicalResponse, source, proofAssessment, recordedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(recordID: c.decode(UUID.self, forKey: .recordID), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID),
                      requestManifest: c.decode(ReviewRequestManifestV1.self, forKey: .requestManifest),
                      canonicalResponse: c.decode(CanonicalReviewResponseBytesV1.self, forKey: .canonicalResponse),
                      source: c.decode(ExternalReviewResponseSourceV1.self, forKey: .source),
                      proofAssessment: c.decode(ReviewProofAssessmentV1.self, forKey: .proofAssessment),
                      recordedAt: c.decode(Date.self, forKey: .recordedAt))
    }
}

/// Binds the frozen exported request to pre-existing C14 review truth without
/// creating a second subject, item ledger, or review writer.
struct ReviewRequestC14SubjectItemMappingV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let requestPublicID: ReviewRequestPublicIDV1
    let subject: InspectionReviewSubjectReferenceV1
    let items: [ChangeRequestItemReferenceV1]

    init(workspaceID: WorkspaceID, requestPublicID: ReviewRequestPublicIDV1,
         subject: InspectionReviewSubjectReferenceV1, items: [ChangeRequestItemReferenceV1]) throws {
        self.workspaceID = workspaceID; self.requestPublicID = requestPublicID; self.subject = subject
        self.items = items.sorted { $0.itemID < $1.itemID }
        try validate()
    }

    func validate() throws {
        try requestPublicID.validate(); try subject.validate()
        try items.forEach { try $0.validate() }
        guard workspaceID == subject.workspaceID,
              Set(items.map(\.itemID)).count == items.count else { throw PortableReviewFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey { case workspaceID, requestPublicID, subject, items }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID),
                      requestPublicID: c.decode(ReviewRequestPublicIDV1.self, forKey: .requestPublicID),
                      subject: c.decode(InspectionReviewSubjectReferenceV1.self, forKey: .subject),
                      items: c.decode([ChangeRequestItemReferenceV1].self, forKey: .items))
    }
}

enum ReviewProofValidityV1: String, Codable, CaseIterable, Hashable, Sendable { case valid = "VALID", invalid = "INVALID", unavailable = "UNAVAILABLE" }
enum ReviewApplicationEligibilityV1: String, Codable, CaseIterable, Hashable, Sendable {
    case eligible = "ELIGIBLE", stale = "STALE", closed = "CLOSED", clonedOrForked = "CLONED_OR_FORKED", superseded = "SUPERSEDED", unavailable = "UNAVAILABLE"
}
struct ReviewProofAssessmentV1: Codable, Equatable, Hashable, Sendable {
    let proofValidity: ReviewProofValidityV1
    let applicationEligibility: ReviewApplicationEligibilityV1
}

enum PortableReviewLifecycleStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case issuedNotExported = "ISSUED_NOT_EXPORTED"
    case exportedAccepting = "EXPORTED_ACCEPTING"
    case responsePendingDecision = "RESPONSE_PENDING_DECISION"
    case historyOnlyTerminal = "HISTORY_ONLY_TERMINAL"
    case historyOnlySuperseded = "HISTORY_ONLY_SUPERSEDED"
    case historyOnlyClonedOrForked = "HISTORY_ONLY_CLONED_OR_FORKED"
    case unavailableCorruptOrMissing = "UNAVAILABLE_CORRUPT_OR_MISSING"
    case erasePending = "ERASE_PENDING"
    case erased = "ERASED"
}

enum ExternalReviewImportDecisionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case acceptAndApply = "ACCEPT_AND_APPLY"
    case recordAsHistoryOnly = "RECORD_AS_HISTORY_ONLY"
    case discardUnimported = "DISCARD_UNIMPORTED"
    case keepQuarantined = "KEEP_QUARANTINED"
}
enum ExternalReviewImportDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case exactPendingDecision = "EXACT_PENDING_DECISION", duplicateAlreadyApplied = "DUPLICATE_ALREADY_APPLIED"
    case staleLocalRevision = "STALE_LOCAL_REVISION", supersededRequest = "SUPERSEDED_REQUEST", unknownRequest = "UNKNOWN_REQUEST"
    case requestDigestMismatch = "REQUEST_DIGEST_MISMATCH", capabilityProofInvalid = "CAPABILITY_PROOF_INVALID"
    case unsupportedProtocol = "UNSUPPORTED_PROTOCOL", itemMappingFailed = "ITEM_MAPPING_FAILED", policyBlocked = "POLICY_BLOCKED"
    case divergentSameResponseID = "DIVERGENT_SAME_RESPONSE_ID"
}
struct ExternalReviewImportPlanV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let requestPublicID: ReviewRequestPublicIDV1
    let basisWorkspaceRevision: UInt64
    let responseRecord: ExternalReviewResponseRecordV1
    let c14Mapping: ReviewRequestC14SubjectItemMappingV1
    let disposition: ExternalReviewImportDispositionV1
    let proofAssessment: ReviewProofAssessmentV1
    let decision: ExternalReviewImportDecisionV1
    let mutationID: MutationIDV1

    init(workspaceID: WorkspaceID, requestPublicID: ReviewRequestPublicIDV1,
         basisWorkspaceRevision: UInt64, responseRecord: ExternalReviewResponseRecordV1,
         c14Mapping: ReviewRequestC14SubjectItemMappingV1,
         disposition: ExternalReviewImportDispositionV1, proofAssessment: ReviewProofAssessmentV1,
         decision: ExternalReviewImportDecisionV1, mutationID: MutationIDV1) throws {
        self.workspaceID = workspaceID; self.requestPublicID = requestPublicID; self.basisWorkspaceRevision = basisWorkspaceRevision
        self.responseRecord = responseRecord; self.c14Mapping = c14Mapping; self.disposition = disposition
        self.proofAssessment = proofAssessment; self.decision = decision; self.mutationID = mutationID
        try validate()
    }

    func validate() throws {
        try requestPublicID.validate(); try responseRecord.validate(); try c14Mapping.validate()
        guard workspaceID.rawValue != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              responseRecord.workspaceID == workspaceID, c14Mapping.workspaceID == workspaceID,
              responseRecord.requestManifest.requestPublicID == requestPublicID,
              c14Mapping.requestPublicID == requestPublicID,
              responseRecord.proofAssessment == proofAssessment else { throw PortableReviewFailureV1.invalidValue }
        if decision == .acceptAndApply {
            guard disposition == .exactPendingDecision,
                  proofAssessment.applicationEligibility == .eligible else { throw PortableReviewFailureV1.ineligibleApplication }
        }
    }

    private enum CodingKeys: String, CodingKey { case workspaceID, requestPublicID, basisWorkspaceRevision, responseRecord, c14Mapping, disposition, proofAssessment, decision, mutationID }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID),
                      requestPublicID: c.decode(ReviewRequestPublicIDV1.self, forKey: .requestPublicID),
                      basisWorkspaceRevision: c.decode(UInt64.self, forKey: .basisWorkspaceRevision),
                      responseRecord: c.decode(ExternalReviewResponseRecordV1.self, forKey: .responseRecord),
                      c14Mapping: c.decode(ReviewRequestC14SubjectItemMappingV1.self, forKey: .c14Mapping),
                      disposition: c.decode(ExternalReviewImportDispositionV1.self, forKey: .disposition),
                      proofAssessment: c.decode(ReviewProofAssessmentV1.self, forKey: .proofAssessment),
                      decision: c.decode(ExternalReviewImportDecisionV1.self, forKey: .decision),
                      mutationID: c.decode(MutationIDV1.self, forKey: .mutationID))
    }
}
struct ExternalReviewImportReceiptV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let basisWorkspaceRevision: UInt64
    let responseRecordID: UUID
    let canonicalResponseSHA256: Data
    let decision: ExternalReviewImportDecisionV1
    let mutationID: MutationIDV1
    let effectDigest: Data
    let proofAssessment: ReviewProofAssessmentV1
    let resultingLifecycleState: PortableReviewLifecycleStateV1
    let appliedWorkspaceRevision: UInt64?

    init(workspaceID: WorkspaceID, basisWorkspaceRevision: UInt64, responseRecord: ExternalReviewResponseRecordV1,
         decision: ExternalReviewImportDecisionV1, mutationID: MutationIDV1, effectDigest: Data,
         proofAssessment: ReviewProofAssessmentV1, resultingLifecycleState: PortableReviewLifecycleStateV1,
         appliedWorkspaceRevision: UInt64?) throws {
        self.workspaceID = workspaceID; self.basisWorkspaceRevision = basisWorkspaceRevision
        responseRecordID = responseRecord.recordID; canonicalResponseSHA256 = responseRecord.canonicalResponse.sha256
        self.decision = decision; self.mutationID = mutationID; self.effectDigest = effectDigest
        self.proofAssessment = proofAssessment; self.resultingLifecycleState = resultingLifecycleState
        self.appliedWorkspaceRevision = appliedWorkspaceRevision
        try validate()
    }

    func validate() throws {
        try PortableReviewLimitsV1.rawDigest(canonicalResponseSHA256)
        try PortableReviewLimitsV1.rawDigest(effectDigest)
        guard workspaceID.rawValue != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              responseRecordID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else { throw PortableReviewFailureV1.invalidIdentity }
        if decision == .acceptAndApply {
            guard proofAssessment.applicationEligibility == .eligible, appliedWorkspaceRevision != nil else {
                throw PortableReviewFailureV1.ineligibleApplication
            }
        } else if appliedWorkspaceRevision != nil {
            throw PortableReviewFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey { case workspaceID, basisWorkspaceRevision, responseRecordID, canonicalResponseSHA256, decision, mutationID, effectDigest, proofAssessment, resultingLifecycleState, appliedWorkspaceRevision }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let recordID = try c.decode(UUID.self, forKey: .responseRecordID)
        let digest = try c.decode(Data.self, forKey: .canonicalResponseSHA256)
        // A receipt cannot reconstruct the immutable record; validate the exact
        // identity/digest fields directly before exposing it to the writer.
        self.workspaceID = try c.decode(WorkspaceID.self, forKey: .workspaceID)
        self.basisWorkspaceRevision = try c.decode(UInt64.self, forKey: .basisWorkspaceRevision)
        self.responseRecordID = recordID; self.canonicalResponseSHA256 = digest
        self.decision = try c.decode(ExternalReviewImportDecisionV1.self, forKey: .decision)
        self.mutationID = try c.decode(MutationIDV1.self, forKey: .mutationID)
        self.effectDigest = try c.decode(Data.self, forKey: .effectDigest)
        self.proofAssessment = try c.decode(ReviewProofAssessmentV1.self, forKey: .proofAssessment)
        self.resultingLifecycleState = try c.decode(PortableReviewLifecycleStateV1.self, forKey: .resultingLifecycleState)
        self.appliedWorkspaceRevision = try c.decodeIfPresent(UInt64.self, forKey: .appliedWorkspaceRevision)
        try validate()
    }
}

enum ReviewRequestProjectionStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case openUnexported = "OPEN_UNEXPORTED", exportedAwaitingResponse = "EXPORTED_AWAITING_RESPONSE"
    case acknowledgedAwaitingDecision = "ACKNOWLEDGED_AWAITING_DECISION", approvalResponseRecorded = "APPROVAL_RESPONSE_RECORDED"
    case changesResponseRecorded = "CHANGES_RESPONSE_RECORDED", superseded = "SUPERSEDED", closedWithoutResponse = "CLOSED_WITHOUT_RESPONSE"
}
struct ReviewRequestStateProjectionV1: Codable, Equatable, Hashable, Sendable {
    let requestPublicID: ReviewRequestPublicIDV1
    let state: ReviewRequestProjectionStateV1
    let lifecycleState: PortableReviewLifecycleStateV1
    let latestResponsePublicID: String?

    init(requestPublicID: ReviewRequestPublicIDV1, state: ReviewRequestProjectionStateV1,
         lifecycleState: PortableReviewLifecycleStateV1, latestResponsePublicID: String? = nil) throws {
        self.requestPublicID = requestPublicID; self.state = state; self.lifecycleState = lifecycleState
        self.latestResponsePublicID = latestResponsePublicID
        try validate()
    }

    func validate() throws {
        try requestPublicID.validate()
        if let latestResponsePublicID { try PortableReviewLimitsV1.canonicalASCII(latestResponsePublicID) }
    }

    private enum CodingKeys: String, CodingKey { case requestPublicID, state, lifecycleState, latestResponsePublicID }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(requestPublicID: c.decode(ReviewRequestPublicIDV1.self, forKey: .requestPublicID),
                      state: c.decode(ReviewRequestProjectionStateV1.self, forKey: .state),
                      lifecycleState: c.decode(PortableReviewLifecycleStateV1.self, forKey: .lifecycleState),
                      latestResponsePublicID: c.decodeIfPresent(String.self, forKey: .latestResponsePublicID))
    }
}

struct ReviewExchangeBudgetV1: Codable, Equatable, Hashable, Sendable {
    let maximumSessions: Int
    let maximumResponseBytes: Int
    init(maximumSessions: Int = PortableReviewLimitsV1.maximumExchangeSessions,
         maximumResponseBytes: Int = PortableReviewLimitsV1.maximumResponseBytes) throws {
        guard maximumSessions > 0, maximumSessions <= PortableReviewLimitsV1.maximumExchangeSessions,
              maximumResponseBytes > 0, maximumResponseBytes <= PortableReviewLimitsV1.maximumResponseBytes else {
            throw PortableReviewFailureV1.invalidValue
        }
        self.maximumSessions = maximumSessions; self.maximumResponseBytes = maximumResponseBytes
    }

    private enum CodingKeys: String, CodingKey { case maximumSessions, maximumResponseBytes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(maximumSessions: c.decode(Int.self, forKey: .maximumSessions),
                      maximumResponseBytes: c.decode(Int.self, forKey: .maximumResponseBytes))
    }
}

// MARK: - C49 work-resource review exchange

enum C49WorkResourceReviewExchangeBoundaryV1 {
    static let exchangeIsPreviewOnly = true
    static let customerSafeProjectionIsRequired = true
    static let internalDirectCostsAreNeverExported = true
    static let sourceBytesAndLiveInventoryRowsAreExcluded = true

    static func customerSafePreview(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws -> C49WorkResourceProjectionEnvelopeV1 {
        let safe = try C49WorkResourcePrivacyTransformBoundaryV1.customerSafe(projection)
        return try C49WorkResourceProjectionSupportV1.envelope(safe, format: "REVIEW_EXCHANGE")
    }
}

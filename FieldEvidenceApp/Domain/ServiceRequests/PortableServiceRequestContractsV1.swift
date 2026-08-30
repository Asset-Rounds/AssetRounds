import CryptoKit
import Foundation
import Security

enum ServiceRequestFailureV1: Error, Equatable, Sendable {
    case invalidIdentity
    case invalidValue
    case invalidDigest
    case invalidCapability
    case invalidProof
    case incompatibleVersion
    case nonCanonicalEncoding
    case unknownKey
    case limitExceeded
    case scopeMismatch
    case proofMismatch
    case ineligibleImport
    case divergentSubmission
    case staleRevision
    case invalidHistory
}

enum ServiceRequestLimitsV1 {
    static let digestByteCount = 32
    static let capabilityByteCount = 32
    static let proofByteCount = 32
    static let maximumPublicIDBytes = 160
    static let maximumTextBytes = 64 * 1_024
    static let maximumContactBytes = 1_024
    static let maximumReasonBytes = 2_048
    static let maximumMediaItems = 16
    static let maximumMediaBytes: UInt64 = 64 * 1_024 * 1_024
    static let maximumSingleMediaBytes: UInt64 = 16 * 1_024 * 1_024
    static let maximumPixelDimension = 16_384
    static let maximumScopedAssets = 16
    static let maximumDuplicateCandidates = 64
    static let maximumRecordsPerMutation = 64
    static let maximumPortableFileBytes = 96 * 1_024 * 1_024

    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func id(_ value: UUID) throws {
        guard value != zeroUUID else { throw ServiceRequestFailureV1.invalidIdentity }
    }

    static func digest(_ value: String) throws {
        guard value.utf8.count == 64,
              value.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw ServiceRequestFailureV1.invalidDigest
        }
    }

    static func rawDigest(_ value: Data) throws {
        guard value.count == digestByteCount else { throw ServiceRequestFailureV1.invalidDigest }
    }

    static func canonicalASCII(_ value: String, maximumBytes: Int = maximumPublicIDBytes) throws {
        guard !value.isEmpty, value.utf8.count <= maximumBytes,
              value.data(using: .ascii)?.count == value.utf8.count,
              !value.utf8.contains(0),
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ServiceRequestFailureV1.nonCanonicalEncoding
        }
    }

    static func text(_ value: String, maximumBytes: Int, permitsEmpty: Bool = false) throws {
        guard (permitsEmpty || !value.isEmpty), value.utf8.count <= maximumBytes,
              value == value.precomposedStringWithCanonicalMapping,
              !value.unicodeScalars.contains(where: { scalar in
                  scalar.value == 0 || scalar.value == 0x7f ||
                  (0x80...0x9f).contains(scalar.value) ||
                  [0x202a, 0x202b, 0x202c, 0x202d, 0x202e].contains(scalar.value)
              }) else { throw ServiceRequestFailureV1.invalidValue }
    }
}

private enum ServiceRequestClosedCodingV1 {
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
        init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
    }

    static func requireExact<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        _ keys: Key.Type
    ) throws where Key.AllCases: Collection {
        let actual = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
        let expected = Set(Key.allCases.map(\.stringValue))
        guard actual == expected else { throw ServiceRequestFailureV1.unknownKey }
    }

    static func requireAllowed<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        _ keys: Key.Type,
        required: [Key]
    ) throws where Key.AllCases: Collection {
        let actual = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
        let allowed = Set(Key.allCases.map(\.stringValue))
        let requiredNames = Set(required.map(\.stringValue))
        guard actual.isSubset(of: allowed), requiredNames.isSubset(of: actual) else {
            throw ServiceRequestFailureV1.unknownKey
        }
    }
}

enum ServiceRequestCanonicalCodecV1 {
    static func data<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        guard try Self.data(value) == data else { throw ServiceRequestFailureV1.nonCanonicalEncoding }
        return value
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try data(value)).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct ServiceRequestInvitationPublicIDV1: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) throws { self.rawValue = rawValue; try validate() }
    init(_ rawValue: String) throws { try self.init(rawValue: rawValue) }
    func validate() throws { try ServiceRequestLimitsV1.canonicalASCII(rawValue) }
    init(from decoder: Decoder) throws { try self.init(try decoder.singleValueContainer().decode(String.self)) }
    func encode(to encoder: Encoder) throws { try validate(); var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

struct ServiceRequestSubmissionPublicIDV1: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) throws { self.rawValue = rawValue; try validate() }
    init(_ rawValue: String) throws { try self.init(rawValue: rawValue) }
    func validate() throws { try ServiceRequestLimitsV1.canonicalASCII(rawValue) }
    init(from decoder: Decoder) throws { try self.init(try decoder.singleValueContainer().decode(String.self)) }
    func encode(to encoder: Encoder) throws { try validate(); var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

enum ServiceRequestMediaFormatV1: String, Codable, CaseIterable, Hashable, Sendable {
    case jpeg = "JPEG"
    case heic = "HEIC"
    case png = "PNG"
}

enum ServiceRequestMediaProvenanceV1: String, Codable, CaseIterable, Hashable, Sendable {
    case recipientSuppliedDerivative = "RECIPIENT_SUPPLIED_DERIVATIVE"
}

struct ServiceRequestExchangeBudgetV1: Codable, Equatable, Hashable, Sendable {
    let maximumScopedAssets: Int
    let maximumMediaItems: Int
    let maximumSingleMediaBytes: UInt64
    let maximumTotalMediaBytes: UInt64
    let maximumSubmissionBytes: Int
    let maximumDuplicateCandidates: Int

    init(
        maximumScopedAssets: Int = ServiceRequestLimitsV1.maximumScopedAssets,
        maximumMediaItems: Int = ServiceRequestLimitsV1.maximumMediaItems,
        maximumSingleMediaBytes: UInt64 = ServiceRequestLimitsV1.maximumSingleMediaBytes,
        maximumTotalMediaBytes: UInt64 = ServiceRequestLimitsV1.maximumMediaBytes,
        maximumSubmissionBytes: Int = ServiceRequestLimitsV1.maximumPortableFileBytes,
        maximumDuplicateCandidates: Int = ServiceRequestLimitsV1.maximumDuplicateCandidates
    ) throws {
        guard (1...ServiceRequestLimitsV1.maximumScopedAssets).contains(maximumScopedAssets),
              (1...ServiceRequestLimitsV1.maximumMediaItems).contains(maximumMediaItems),
              maximumSingleMediaBytes > 0,
              maximumSingleMediaBytes <= ServiceRequestLimitsV1.maximumSingleMediaBytes,
              maximumTotalMediaBytes >= maximumSingleMediaBytes,
              maximumTotalMediaBytes <= ServiceRequestLimitsV1.maximumMediaBytes,
              maximumSubmissionBytes > 0,
              maximumSubmissionBytes <= ServiceRequestLimitsV1.maximumPortableFileBytes,
              (1...ServiceRequestLimitsV1.maximumDuplicateCandidates).contains(maximumDuplicateCandidates) else {
            throw ServiceRequestFailureV1.limitExceeded
        }
        self.maximumScopedAssets = maximumScopedAssets
        self.maximumMediaItems = maximumMediaItems
        self.maximumSingleMediaBytes = maximumSingleMediaBytes
        self.maximumTotalMediaBytes = maximumTotalMediaBytes
        self.maximumSubmissionBytes = maximumSubmissionBytes
        self.maximumDuplicateCandidates = maximumDuplicateCandidates
    }

    func validate() throws {
        guard (1...ServiceRequestLimitsV1.maximumScopedAssets).contains(maximumScopedAssets),
              (1...ServiceRequestLimitsV1.maximumMediaItems).contains(maximumMediaItems),
              maximumSingleMediaBytes > 0,
              maximumSingleMediaBytes <= ServiceRequestLimitsV1.maximumSingleMediaBytes,
              maximumTotalMediaBytes >= maximumSingleMediaBytes,
              maximumTotalMediaBytes <= ServiceRequestLimitsV1.maximumMediaBytes,
              maximumSubmissionBytes > 0,
              maximumSubmissionBytes <= ServiceRequestLimitsV1.maximumPortableFileBytes,
              (1...ServiceRequestLimitsV1.maximumDuplicateCandidates).contains(maximumDuplicateCandidates) else {
            throw ServiceRequestFailureV1.limitExceeded
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case maximumScopedAssets, maximumMediaItems, maximumSingleMediaBytes
        case maximumTotalMediaBytes, maximumSubmissionBytes, maximumDuplicateCandidates
    }

    init(from decoder: Decoder) throws {
        try ServiceRequestClosedCodingV1.requireExact(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            maximumScopedAssets: try c.decode(Int.self, forKey: .maximumScopedAssets),
            maximumMediaItems: try c.decode(Int.self, forKey: .maximumMediaItems),
            maximumSingleMediaBytes: try c.decode(UInt64.self, forKey: .maximumSingleMediaBytes),
            maximumTotalMediaBytes: try c.decode(UInt64.self, forKey: .maximumTotalMediaBytes),
            maximumSubmissionBytes: try c.decode(Int.self, forKey: .maximumSubmissionBytes),
            maximumDuplicateCandidates: try c.decode(Int.self, forKey: .maximumDuplicateCandidates)
        )
    }
}

/// Immutable release authority. Service-request packages are deliberately
/// cleartext and are never valid inner kinds of `.arenvelope` in V1.
struct PortableServiceRequestProtocolReleaseV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    static let proofDomain = "AssetRounds.ServiceRequestCapabilityProof.V1"
    static let invitationExtension = "arserviceinvite"
    static let submissionExtension = "arservicesubmission"

    let schemaVersion: Int
    let protocolID: String
    let protocolVersion: Int
    let invitationSchemaID: String
    let submissionSchemaID: String
    let invitationFileExtension: String
    let submissionFileExtension: String
    let proofDomain: String
    let cleartextReadableAndForwardable: Bool
    let envelopeInnerKindPermitted: Bool
    let allowedMediaFormats: [ServiceRequestMediaFormatV1]
    let budget: ServiceRequestExchangeBudgetV1
    let releaseSHA256: String

    init(
        protocolID: String = "PORTABLE_SERVICE_REQUEST_V1",
        protocolVersion: Int = 1,
        invitationSchemaID: String = "AR_SERVICE_INVITATION_V1",
        submissionSchemaID: String = "AR_SERVICE_SUBMISSION_V1",
        budget: ServiceRequestExchangeBudgetV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.protocolID = protocolID
        self.protocolVersion = protocolVersion
        self.invitationSchemaID = invitationSchemaID
        self.submissionSchemaID = submissionSchemaID
        invitationFileExtension = Self.invitationExtension
        submissionFileExtension = Self.submissionExtension
        proofDomain = Self.proofDomain
        cleartextReadableAndForwardable = true
        envelopeInnerKindPermitted = false
        allowedMediaFormats = ServiceRequestMediaFormatV1.allCases
        self.budget = budget
        releaseSHA256 = try ServiceRequestCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, protocolID: protocolID, protocolVersion: protocolVersion,
            invitationSchemaID: invitationSchemaID, submissionSchemaID: submissionSchemaID,
            invitationFileExtension: Self.invitationExtension, submissionFileExtension: Self.submissionExtension,
            proofDomain: Self.proofDomain, cleartextReadableAndForwardable: true,
            envelopeInnerKindPermitted: false, allowedMediaFormats: ServiceRequestMediaFormatV1.allCases,
            budget: budget
        ))
        try validate()
    }

    func validate() throws {
        try budget.validate()
        try ServiceRequestLimitsV1.canonicalASCII(protocolID)
        try ServiceRequestLimitsV1.canonicalASCII(invitationSchemaID)
        try ServiceRequestLimitsV1.canonicalASCII(submissionSchemaID)
        try ServiceRequestLimitsV1.digest(releaseSHA256)
        guard schemaVersion == Self.schemaVersion, protocolVersion == 1,
              invitationFileExtension == Self.invitationExtension,
              submissionFileExtension == Self.submissionExtension,
              proofDomain == Self.proofDomain, cleartextReadableAndForwardable,
              !envelopeInnerKindPermitted,
              allowedMediaFormats == ServiceRequestMediaFormatV1.allCases,
              releaseSHA256 == (try ServiceRequestCanonicalCodecV1.sha256(basis)) else {
            throw ServiceRequestFailureV1.invalidValue
        }
    }

    private var basis: Basis { .init(
        schemaVersion: schemaVersion, protocolID: protocolID, protocolVersion: protocolVersion,
        invitationSchemaID: invitationSchemaID, submissionSchemaID: submissionSchemaID,
        invitationFileExtension: invitationFileExtension, submissionFileExtension: submissionFileExtension,
        proofDomain: proofDomain, cleartextReadableAndForwardable: cleartextReadableAndForwardable,
        envelopeInnerKindPermitted: envelopeInnerKindPermitted, allowedMediaFormats: allowedMediaFormats, budget: budget
    ) }
    private struct Basis: Codable { let schemaVersion:Int;let protocolID:String;let protocolVersion:Int;let invitationSchemaID:String;let submissionSchemaID:String;let invitationFileExtension:String;let submissionFileExtension:String;let proofDomain:String;let cleartextReadableAndForwardable:Bool;let envelopeInnerKindPermitted:Bool;let allowedMediaFormats:[ServiceRequestMediaFormatV1];let budget:ServiceRequestExchangeBudgetV1 }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion,protocolID,protocolVersion,invitationSchemaID,submissionSchemaID,invitationFileExtension,submissionFileExtension,proofDomain,cleartextReadableAndForwardable,envelopeInnerKindPermitted,allowedMediaFormats,budget,releaseSHA256 }
    init(from decoder: Decoder) throws {
        try ServiceRequestClosedCodingV1.requireExact(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rebuilt = try Self(protocolID:try c.decode(String.self,forKey:.protocolID),protocolVersion:try c.decode(Int.self,forKey:.protocolVersion),invitationSchemaID:try c.decode(String.self,forKey:.invitationSchemaID),submissionSchemaID:try c.decode(String.self,forKey:.submissionSchemaID),budget:try c.decode(ServiceRequestExchangeBudgetV1.self,forKey:.budget))
        guard try c.decode(Int.self,forKey:.schemaVersion)==Self.schemaVersion,
              try c.decode(String.self,forKey:.invitationFileExtension)==rebuilt.invitationFileExtension,
              try c.decode(String.self,forKey:.submissionFileExtension)==rebuilt.submissionFileExtension,
              try c.decode(String.self,forKey:.proofDomain)==rebuilt.proofDomain,
              try c.decode(Bool.self,forKey:.cleartextReadableAndForwardable)==rebuilt.cleartextReadableAndForwardable,
              try c.decode(Bool.self,forKey:.envelopeInnerKindPermitted)==rebuilt.envelopeInnerKindPermitted,
              try c.decode([ServiceRequestMediaFormatV1].self,forKey:.allowedMediaFormats)==rebuilt.allowedMediaFormats,
              try c.decode(String.self,forKey:.releaseSHA256)==rebuilt.releaseSHA256 else { throw ServiceRequestFailureV1.invalidDigest }
        self = rebuilt
    }
}

/// Deliberately non-Codable. The only portable encoding of these bytes is the
/// explicit capability field inside `PortableServiceRequestInvitationV1`.
struct ServiceRequestSubmissionCapabilityV1: Equatable, Hashable, Sendable {
    let rawBytes: Data
    init(rawBytes: Data) throws {
        guard rawBytes.count == ServiceRequestLimitsV1.capabilityByteCount else { throw ServiceRequestFailureV1.invalidCapability }
        self.rawBytes = rawBytes
    }
    static func issue() throws -> Self {
        var bytes = Data(repeating: 0, count: ServiceRequestLimitsV1.capabilityByteCount)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, ServiceRequestLimitsV1.capabilityByteCount, base)
        }
        guard status == errSecSuccess else { throw ServiceRequestFailureV1.invalidCapability }
        return try Self(rawBytes: bytes)
    }
}

struct ServiceRequestCapabilityProofV1: Codable, Equatable, Hashable, Sendable {
    let rawBytes: Data
    init(rawBytes: Data) throws {
        guard rawBytes.count == ServiceRequestLimitsV1.proofByteCount else { throw ServiceRequestFailureV1.invalidProof }
        self.rawBytes = rawBytes
    }
    init(from decoder: Decoder) throws { try self.init(rawBytes: decoder.singleValueContainer().decode(Data.self)) }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawBytes) }
}

struct ServiceRequestCapabilityProofInputV1: Equatable, Sendable {
    let protocolReleaseDigest: Data
    let invitationPublicID: ServiceRequestInvitationPublicIDV1
    let invitationManifestDigest: Data
    let frozenScopeSnapshotDigest: Data
    let submissionPublicID: ServiceRequestSubmissionPublicIDV1
    let canonicalSubmissionBodyDigest: Data
    let mediaManifestDigest: Data
    init(protocolReleaseDigest:Data,invitationPublicID:ServiceRequestInvitationPublicIDV1,invitationManifestDigest:Data,frozenScopeSnapshotDigest:Data,submissionPublicID:ServiceRequestSubmissionPublicIDV1,canonicalSubmissionBodyDigest:Data,mediaManifestDigest:Data)throws{
        self.protocolReleaseDigest=protocolReleaseDigest;self.invitationPublicID=invitationPublicID;self.invitationManifestDigest=invitationManifestDigest;self.frozenScopeSnapshotDigest=frozenScopeSnapshotDigest;self.submissionPublicID=submissionPublicID;self.canonicalSubmissionBodyDigest=canonicalSubmissionBodyDigest;self.mediaManifestDigest=mediaManifestDigest
        try [protocolReleaseDigest,invitationManifestDigest,frozenScopeSnapshotDigest,canonicalSubmissionBodyDigest,mediaManifestDigest].forEach(ServiceRequestLimitsV1.rawDigest);try invitationPublicID.validate();try submissionPublicID.validate()
    }
}

enum ServiceRequestCapabilityProofCodecV1 {
    static func transcript(for input: ServiceRequestCapabilityProofInputV1) throws -> Data {
        guard let domain = PortableServiceRequestProtocolReleaseV1.proofDomain.data(using:.ascii),
              let invitationID=input.invitationPublicID.rawValue.data(using:.ascii),
              let submissionID=input.submissionPublicID.rawValue.data(using:.ascii) else { throw ServiceRequestFailureV1.nonCanonicalEncoding }
        var result=Data();result.append(domain);result.append(0)
        for value in [input.protocolReleaseDigest,invitationID,input.invitationManifestDigest,input.frozenScopeSnapshotDigest,submissionID,input.canonicalSubmissionBodyDigest,input.mediaManifestDigest] { try appendLP(value,to:&result) }
        return result
    }
    static func makeProof(capability:ServiceRequestSubmissionCapabilityV1,input:ServiceRequestCapabilityProofInputV1)throws->ServiceRequestCapabilityProofV1{
        try .init(rawBytes:Data(HMAC<SHA256>.authenticationCode(for:try transcript(for:input),using:SymmetricKey(data:capability.rawBytes))))
    }
    static func verify(_ proof:ServiceRequestCapabilityProofV1,capability:ServiceRequestSubmissionCapabilityV1,input:ServiceRequestCapabilityProofInputV1)throws->Bool{
        constantTimeEqual(try makeProof(capability:capability,input:input).rawBytes,proof.rawBytes)
    }
    static func constantTimeEqual(_ lhs:Data,_ rhs:Data)->Bool{
        guard lhs.count==ServiceRequestLimitsV1.proofByteCount,rhs.count==ServiceRequestLimitsV1.proofByteCount else{return false};var difference:UInt8=0;for (a,b) in zip(lhs,rhs){difference |= a ^ b};return difference==0
    }
    private static func appendLP(_ value:Data,to result:inout Data)throws{guard value.count<=Int(UInt32.max)else{throw ServiceRequestFailureV1.limitExceeded};var length=UInt32(value.count).bigEndian;withUnsafeBytes(of:&length){result.append(contentsOf:$0)};result.append(value)}
}

struct ServiceRequestAssetScopeSnapshotV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let assetID: UUID;let expectedRevision:UInt64;let semanticSHA256:String
    init(assetID:UUID,expectedRevision:UInt64,semanticSHA256:String)throws{try ServiceRequestLimitsV1.id(assetID);try ServiceRequestLimitsV1.digest(semanticSHA256);guard expectedRevision>0 else{throw ServiceRequestFailureV1.invalidValue};self.assetID=assetID;self.expectedRevision=expectedRevision;self.semanticSHA256=semanticSHA256}
    func validate()throws{try ServiceRequestLimitsV1.id(assetID);try ServiceRequestLimitsV1.digest(semanticSHA256);guard expectedRevision>0 else{throw ServiceRequestFailureV1.invalidValue}}
    static func <(l:Self,r:Self)->Bool{l.assetID.uuidString<r.assetID.uuidString}
}

struct ServiceRequestScopeSnapshotV1: Codable, Equatable, Hashable, Sendable {
    let siteID:UUID;let siteExpectedRevision:UInt64;let siteSemanticSHA256:String;let assets:[ServiceRequestAssetScopeSnapshotV1];let scopeSHA256:String
    init(siteID:UUID,siteExpectedRevision:UInt64,siteSemanticSHA256:String,assets:[ServiceRequestAssetScopeSnapshotV1]=[])throws{let ordered=assets.sorted();try ServiceRequestLimitsV1.id(siteID);try ServiceRequestLimitsV1.digest(siteSemanticSHA256);try ordered.forEach{$0.validate()};guard siteExpectedRevision>0,ordered.count<=ServiceRequestLimitsV1.maximumScopedAssets,Set(ordered.map(\.assetID)).count==ordered.count else{throw ServiceRequestFailureV1.limitExceeded};self.siteID=siteID;self.siteExpectedRevision=siteExpectedRevision;self.siteSemanticSHA256=siteSemanticSHA256;self.assets=ordered;scopeSHA256=try ServiceRequestCanonicalCodecV1.sha256(Basis(siteID:siteID,siteExpectedRevision:siteExpectedRevision,siteSemanticSHA256:siteSemanticSHA256,assets:ordered))}
    func validate()throws{try ServiceRequestLimitsV1.id(siteID);try ServiceRequestLimitsV1.digest(siteSemanticSHA256);try ServiceRequestLimitsV1.digest(scopeSHA256);try assets.forEach{$0.validate()};guard siteExpectedRevision>0,assets==assets.sorted(),assets.count<=ServiceRequestLimitsV1.maximumScopedAssets,Set(assets.map(\.assetID)).count==assets.count,scopeSHA256==(try ServiceRequestCanonicalCodecV1.sha256(Basis(siteID:siteID,siteExpectedRevision:siteExpectedRevision,siteSemanticSHA256:siteSemanticSHA256,assets:assets)))else{throw ServiceRequestFailureV1.invalidDigest}}
    private struct Basis:Codable{let siteID:UUID;let siteExpectedRevision:UInt64;let siteSemanticSHA256:String;let assets:[ServiceRequestAssetScopeSnapshotV1]}
    private enum CodingKeys:String,CodingKey,CaseIterable{case siteID,siteExpectedRevision,siteSemanticSHA256,assets,scopeSHA256}
    init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let rebuilt=try Self(siteID:try c.decode(UUID.self,forKey:.siteID),siteExpectedRevision:try c.decode(UInt64.self,forKey:.siteExpectedRevision),siteSemanticSHA256:try c.decode(String.self,forKey:.siteSemanticSHA256),assets:try c.decode([ServiceRequestAssetScopeSnapshotV1].self,forKey:.assets));guard try c.decode(String.self,forKey:.scopeSHA256)==rebuilt.scopeSHA256 else{throw ServiceRequestFailureV1.invalidDigest};self=rebuilt}
}

struct ServiceRequestInvitationManifestV1: Codable, Equatable, Hashable, Sendable {
    let protocolReleaseSHA256:String;let invitationPublicID:ServiceRequestInvitationPublicIDV1;let scope:ServiceRequestScopeSnapshotV1;let singleUse:Bool;let manifestSHA256:String
    init(protocolRelease:PortableServiceRequestProtocolReleaseV1,invitationPublicID:ServiceRequestInvitationPublicIDV1,scope:ServiceRequestScopeSnapshotV1)throws{try protocolRelease.validate();try scope.validate();protocolReleaseSHA256=protocolRelease.releaseSHA256;self.invitationPublicID=invitationPublicID;self.scope=scope;singleUse=true;manifestSHA256=try ServiceRequestCanonicalCodecV1.sha256(Basis(protocolReleaseSHA256:protocolRelease.releaseSHA256,invitationPublicID:invitationPublicID,scope:scope,singleUse:true))}
    func validate()throws{try ServiceRequestLimitsV1.digest(protocolReleaseSHA256);try invitationPublicID.validate();try scope.validate();guard singleUse,manifestSHA256==(try ServiceRequestCanonicalCodecV1.sha256(Basis(protocolReleaseSHA256:protocolReleaseSHA256,invitationPublicID:invitationPublicID,scope:scope,singleUse:singleUse)))else{throw ServiceRequestFailureV1.invalidDigest}}
    private struct Basis:Codable{let protocolReleaseSHA256:String;let invitationPublicID:ServiceRequestInvitationPublicIDV1;let scope:ServiceRequestScopeSnapshotV1;let singleUse:Bool}
    private enum CodingKeys:String,CodingKey,CaseIterable{case protocolReleaseSHA256,invitationPublicID,scope,singleUse,manifestSHA256}
    init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);protocolReleaseSHA256=try c.decode(String.self,forKey:.protocolReleaseSHA256);invitationPublicID=try c.decode(ServiceRequestInvitationPublicIDV1.self,forKey:.invitationPublicID);scope=try c.decode(ServiceRequestScopeSnapshotV1.self,forKey:.scope);singleUse=try c.decode(Bool.self,forKey:.singleUse);manifestSHA256=try c.decode(String.self,forKey:.manifestSHA256);try validate()}
}

struct PortableServiceRequestInvitationV1: Codable, Equatable, Sendable {
    let manifest:ServiceRequestInvitationManifestV1;let submissionCapabilityBytes:Data
    init(manifest:ServiceRequestInvitationManifestV1,capability:ServiceRequestSubmissionCapabilityV1)throws{try manifest.validate();self.manifest=manifest;submissionCapabilityBytes=capability.rawBytes}
    var capability:ServiceRequestSubmissionCapabilityV1{get throws{try .init(rawBytes:submissionCapabilityBytes)}}
    func validate()throws{try manifest.validate();_ = try capability}
    private enum CodingKeys:String,CodingKey,CaseIterable{case manifest,submissionCapabilityBytes}
    init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);manifest=try c.decode(ServiceRequestInvitationManifestV1.self,forKey:.manifest);submissionCapabilityBytes=try c.decode(Data.self,forKey:.submissionCapabilityBytes);try validate()}
}

struct ServiceRequestMediaEntryV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let mediaID:String;let format:ServiceRequestMediaFormatV1;let byteCount:UInt64;let pixelWidth:Int;let pixelHeight:Int;let sha256:String;let orientationBaked:Bool;let metadataStripped:Bool;let provenance:ServiceRequestMediaProvenanceV1
    init(mediaID:String,format:ServiceRequestMediaFormatV1,byteCount:UInt64,pixelWidth:Int,pixelHeight:Int,sha256:String)throws{try ServiceRequestLimitsV1.canonicalASCII(mediaID);try ServiceRequestLimitsV1.digest(sha256);guard byteCount>0,byteCount<=ServiceRequestLimitsV1.maximumSingleMediaBytes,(1...ServiceRequestLimitsV1.maximumPixelDimension).contains(pixelWidth),(1...ServiceRequestLimitsV1.maximumPixelDimension).contains(pixelHeight)else{throw ServiceRequestFailureV1.limitExceeded};self.mediaID=mediaID;self.format=format;self.byteCount=byteCount;self.pixelWidth=pixelWidth;self.pixelHeight=pixelHeight;self.sha256=sha256;orientationBaked=true;metadataStripped=true;provenance = .recipientSuppliedDerivative}
    func validate()throws{try ServiceRequestLimitsV1.canonicalASCII(mediaID);try ServiceRequestLimitsV1.digest(sha256);guard byteCount>0,byteCount<=ServiceRequestLimitsV1.maximumSingleMediaBytes,(1...ServiceRequestLimitsV1.maximumPixelDimension).contains(pixelWidth),(1...ServiceRequestLimitsV1.maximumPixelDimension).contains(pixelHeight),orientationBaked,metadataStripped,provenance == .recipientSuppliedDerivative else{throw ServiceRequestFailureV1.limitExceeded}}
    static func <(l:Self,r:Self)->Bool{l.mediaID<r.mediaID}
}

struct ServiceRequestMediaManifestV1: Codable, Equatable, Hashable, Sendable {
    let entries:[ServiceRequestMediaEntryV1];let totalByteCount:UInt64;let manifestSHA256:String
    init(entries:[ServiceRequestMediaEntryV1])throws{let ordered=entries.sorted();try ordered.forEach{$0.validate()};guard ordered.count<=ServiceRequestLimitsV1.maximumMediaItems,Set(ordered.map(\.mediaID)).count==ordered.count else{throw ServiceRequestFailureV1.limitExceeded};var total:UInt64=0;for entry in ordered{let(next,overflow)=total.addingReportingOverflow(entry.byteCount);guard !overflow,next<=ServiceRequestLimitsV1.maximumMediaBytes else{throw ServiceRequestFailureV1.limitExceeded};total=next};self.entries=ordered;totalByteCount=total;manifestSHA256=try ServiceRequestCanonicalCodecV1.sha256(Basis(entries:ordered,totalByteCount:total))}
    func validate()throws{try entries.forEach{$0.validate()};guard entries==entries.sorted(),entries.count<=ServiceRequestLimitsV1.maximumMediaItems,Set(entries.map(\.mediaID)).count==entries.count else{throw ServiceRequestFailureV1.limitExceeded};var total:UInt64=0;for entry in entries{let(next,overflow)=total.addingReportingOverflow(entry.byteCount);guard !overflow,next<=ServiceRequestLimitsV1.maximumMediaBytes else{throw ServiceRequestFailureV1.limitExceeded};total=next};guard totalByteCount==total,manifestSHA256==(try ServiceRequestCanonicalCodecV1.sha256(Basis(entries:entries,totalByteCount:totalByteCount)))else{throw ServiceRequestFailureV1.invalidDigest}}
    private struct Basis:Codable{let entries:[ServiceRequestMediaEntryV1];let totalByteCount:UInt64}
    private enum CodingKeys:String,CodingKey,CaseIterable{case entries,totalByteCount,manifestSHA256}
    init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let rebuilt=try Self(entries:try c.decode([ServiceRequestMediaEntryV1].self,forKey:.entries));guard try c.decode(UInt64.self,forKey:.totalByteCount)==rebuilt.totalByteCount,try c.decode(String.self,forKey:.manifestSHA256)==rebuilt.manifestSHA256 else{throw ServiceRequestFailureV1.invalidDigest};self=rebuilt}
}

enum ServiceRequestUrgencyAssertionV1:String,Codable,CaseIterable,Hashable,Sendable{case unspecified="UNSPECIFIED";case routine="ROUTINE";case soon="SOON";case urgentSelfAsserted="URGENT_SELF_ASSERTED"}
struct ServiceRequestRequesterAssertionV1:Codable,Equatable,Hashable,Sendable{
    let displayName:String?;let organization:String?
    init(displayName:String?=nil,organization:String?=nil)throws{self.displayName=displayName;self.organization=organization;try validate()}
    func validate()throws{if let displayName{try ServiceRequestLimitsV1.text(displayName,maximumBytes:160)};if let organization{try ServiceRequestLimitsV1.text(organization,maximumBytes:160)};guard displayName != nil || organization != nil else{throw ServiceRequestFailureV1.invalidValue}}
    private enum CodingKeys:String,CodingKey,CaseIterable{case displayName,organization}
    init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireAllowed(decoder,CodingKeys.self,required:[]);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(displayName:try c.decodeIfPresent(String.self,forKey:.displayName),organization:try c.decodeIfPresent(String.self,forKey:.organization))}
}
struct ServiceRequestContactAssertionV1:Codable,Equatable,Hashable,Sendable{
    static let unverifiedWording="SELF_ASSERTED_UNVERIFIED"
    let value:String?;let wording:String
    init(value:String?,wording:String=Self.unverifiedWording)throws{self.value=value;self.wording=wording;try validate()}
    func validate()throws{if let value{try ServiceRequestLimitsV1.text(value,maximumBytes:ServiceRequestLimitsV1.maximumContactBytes)};guard wording==Self.unverifiedWording else{throw ServiceRequestFailureV1.invalidValue}}
    private enum CodingKeys:String,CodingKey,CaseIterable{case value,wording}
    init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireAllowed(decoder,CodingKeys.self,required:[.wording]);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(value:try c.decodeIfPresent(String.self,forKey:.value),wording:try c.decode(String.self,forKey:.wording))}
}
struct ServiceRequestSubmissionBodyV1:Codable,Equatable,Hashable,Sendable{
    let requestText:String;let statedDate:Date?;let urgency:ServiceRequestUrgencyAssertionV1;let requester:ServiceRequestRequesterAssertionV1;let contact:ServiceRequestContactAssertionV1;let category:String?
    init(requestText:String,statedDate:Date?=nil,urgency:ServiceRequestUrgencyAssertionV1,requester:ServiceRequestRequesterAssertionV1,contact:ServiceRequestContactAssertionV1,category:String?=nil)throws{self.requestText=requestText;self.statedDate=statedDate;self.urgency=urgency;self.requester=requester;self.contact=contact;self.category=category;try validate()}
    func validate()throws{try ServiceRequestLimitsV1.text(requestText,maximumBytes:ServiceRequestLimitsV1.maximumTextBytes);if let statedDate,!statedDate.timeIntervalSinceReferenceDate.isFinite{throw ServiceRequestFailureV1.invalidValue};try requester.validate();try contact.validate();if let category{try ServiceRequestLimitsV1.text(category,maximumBytes:160)}}
    private enum CodingKeys:String,CodingKey,CaseIterable{case requestText,statedDate,urgency,requester,contact,category}
    init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireAllowed(decoder,CodingKeys.self,required:[.requestText,.urgency,.requester,.contact]);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(requestText:try c.decode(String.self,forKey:.requestText),statedDate:try c.decodeIfPresent(Date.self,forKey:.statedDate),urgency:try c.decode(ServiceRequestUrgencyAssertionV1.self,forKey:.urgency),requester:try c.decode(ServiceRequestRequesterAssertionV1.self,forKey:.requester),contact:try c.decode(ServiceRequestContactAssertionV1.self,forKey:.contact),category:try c.decodeIfPresent(String.self,forKey:.category))}
}

struct PortableServiceRequestSubmissionV1:Codable,Equatable,Sendable{
    let protocolReleaseSHA256:String;let invitationPublicID:ServiceRequestInvitationPublicIDV1;let invitationManifestSHA256:String;let frozenScopeSHA256:String;let submissionPublicID:ServiceRequestSubmissionPublicIDV1;let body:ServiceRequestSubmissionBodyV1;let canonicalBodySHA256:String;let mediaManifest:ServiceRequestMediaManifestV1;let proof:ServiceRequestCapabilityProofV1
    init(protocolReleaseSHA256:String,invitationManifest:ServiceRequestInvitationManifestV1,submissionPublicID:ServiceRequestSubmissionPublicIDV1,body:ServiceRequestSubmissionBodyV1,mediaManifest:ServiceRequestMediaManifestV1,proof:ServiceRequestCapabilityProofV1)throws{try ServiceRequestLimitsV1.digest(protocolReleaseSHA256);try invitationManifest.validate();try mediaManifest.validate();self.protocolReleaseSHA256=protocolReleaseSHA256;invitationPublicID=invitationManifest.invitationPublicID;invitationManifestSHA256=invitationManifest.manifestSHA256;frozenScopeSHA256=invitationManifest.scope.scopeSHA256;self.submissionPublicID=submissionPublicID;self.body=body;canonicalBodySHA256=try ServiceRequestCanonicalCodecV1.sha256(body);self.mediaManifest=mediaManifest;self.proof=proof;try validate()}
    func validate()throws{try body.validate();try mediaManifest.validate();try [protocolReleaseSHA256,invitationManifestSHA256,frozenScopeSHA256,canonicalBodySHA256,mediaManifest.manifestSHA256].forEach(ServiceRequestLimitsV1.digest);guard canonicalBodySHA256==(try ServiceRequestCanonicalCodecV1.sha256(body))else{throw ServiceRequestFailureV1.invalidDigest}}
    private enum CodingKeys:String,CodingKey,CaseIterable{case protocolReleaseSHA256,invitationPublicID,invitationManifestSHA256,frozenScopeSHA256,submissionPublicID,body,canonicalBodySHA256,mediaManifest,proof}
    init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);protocolReleaseSHA256=try c.decode(String.self,forKey:.protocolReleaseSHA256);invitationPublicID=try c.decode(ServiceRequestInvitationPublicIDV1.self,forKey:.invitationPublicID);invitationManifestSHA256=try c.decode(String.self,forKey:.invitationManifestSHA256);frozenScopeSHA256=try c.decode(String.self,forKey:.frozenScopeSHA256);submissionPublicID=try c.decode(ServiceRequestSubmissionPublicIDV1.self,forKey:.submissionPublicID);body=try c.decode(ServiceRequestSubmissionBodyV1.self,forKey:.body);canonicalBodySHA256=try c.decode(String.self,forKey:.canonicalBodySHA256);mediaManifest=try c.decode(ServiceRequestMediaManifestV1.self,forKey:.mediaManifest);proof=try c.decode(ServiceRequestCapabilityProofV1.self,forKey:.proof);try validate()}
}

enum PortableServiceRequestFormatBoundaryV1 {
    static let invitationIsCleartext = true
    static let submissionIsCleartext = true
    static let invitationIsReadableAndForwardable = true
    static let forwardingTransfersSubmissionAbility = true
    static let sharingProvesDelivery = false
    static let requesterIdentityIsVerified = false
    static let urgencyIsVerified = false
    static let serviceRequestEnvelopeInnerKindPermitted = false
}

enum ServiceRequestSourceKindV1:String,Codable,CaseIterable,Hashable,Sendable{case portableSubmission="PORTABLE_SUBMISSION";case phone="PHONE";case email="EMAIL";case text="TEXT";case paper="PAPER";case inPerson="IN_PERSON";case other="OTHER"}
enum ServiceRequestProofValidityV1:String,Codable,CaseIterable,Hashable,Sendable{case valid="VALID";case invalid="INVALID";case unavailable="UNAVAILABLE"}
enum ServiceRequestImportEligibilityV1:String,Codable,CaseIterable,Hashable,Sendable{case eligible="ELIGIBLE";case invitationTerminal="INVITATION_TERMINAL";case staleScope="STALE_SCOPE";case targetMoved="TARGET_MOVED";case targetRetired="TARGET_RETIRED";case targetDeleted="TARGET_DELETED";case clonedOrForked="CLONED_OR_FORKED";case unavailable="UNAVAILABLE"}
struct ServiceRequestCapabilityAssessmentV1:Codable,Equatable,Hashable,Sendable{let proofValidity:ServiceRequestProofValidityV1;let importEligibility:ServiceRequestImportEligibilityV1}

struct CanonicalServiceRequestSourceBytesV1:Codable,Equatable,Hashable,Sendable{let bytes:Data;let byteCount:Int;let sha256:String;init(_ bytes:Data)throws{guard !bytes.isEmpty,bytes.count<=ServiceRequestLimitsV1.maximumPortableFileBytes else{throw ServiceRequestFailureV1.limitExceeded};self.bytes=bytes;byteCount=bytes.count;sha256=ServiceRequestCanonicalCodecV1.sha256(bytes)};func validate()throws{guard !bytes.isEmpty,bytes.count<=ServiceRequestLimitsV1.maximumPortableFileBytes,byteCount==bytes.count,sha256==ServiceRequestCanonicalCodecV1.sha256(bytes)else{throw ServiceRequestFailureV1.invalidDigest}};private enum CodingKeys:String,CodingKey,CaseIterable{case bytes,byteCount,sha256};init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let rebuilt=try Self(try c.decode(Data.self,forKey:.bytes));guard try c.decode(Int.self,forKey:.byteCount)==rebuilt.byteCount,try c.decode(String.self,forKey:.sha256)==rebuilt.sha256 else{throw ServiceRequestFailureV1.invalidDigest};self=rebuilt}}

struct ServiceRequestRevisionReferenceV1:Codable,Equatable,Hashable,Sendable{let recordID:UUID;let revision:UInt64;let recordSHA256:String;init(recordID:UUID,revision:UInt64,recordSHA256:String)throws{self.recordID=recordID;self.revision=revision;self.recordSHA256=recordSHA256;try validate()};func validate()throws{try ServiceRequestLimitsV1.id(recordID);try ServiceRequestLimitsV1.digest(recordSHA256);guard revision>0 else{throw ServiceRequestFailureV1.invalidValue}};private enum CodingKeys:String,CodingKey,CaseIterable{case recordID,revision,recordSHA256};init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(recordID:try c.decode(UUID.self,forKey:.recordID),revision:try c.decode(UInt64.self,forKey:.revision),recordSHA256:try c.decode(String.self,forKey:.recordSHA256))}}

struct ServiceRequestRecordV1:Codable,Equatable,Hashable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let recordID:UUID;let workspaceID:WorkspaceID;let submissionPublicID:ServiceRequestSubmissionPublicIDV1?;let invitationPublicID:ServiceRequestInvitationPublicIDV1?;let source:ServiceRequestSourceKindV1;let scope:ServiceRequestScopeSnapshotV1;let body:ServiceRequestSubmissionBodyV1;let mediaManifest:ServiceRequestMediaManifestV1;let acceptedSourceBytes:CanonicalServiceRequestSourceBytesV1?;let capabilityAssessment:ServiceRequestCapabilityAssessmentV1;let supersedes:ServiceRequestRevisionReferenceV1?;let revision:UInt64;let mutationID:MutationIDV1;let recordedAt:Date;let recordSHA256:String
    init(recordID:UUID,workspaceID:WorkspaceID,submissionPublicID:ServiceRequestSubmissionPublicIDV1?=nil,invitationPublicID:ServiceRequestInvitationPublicIDV1?=nil,source:ServiceRequestSourceKindV1,scope:ServiceRequestScopeSnapshotV1,body:ServiceRequestSubmissionBodyV1,mediaManifest:ServiceRequestMediaManifestV1,acceptedSourceBytes:CanonicalServiceRequestSourceBytesV1?=nil,capabilityAssessment:ServiceRequestCapabilityAssessmentV1,supersedes:ServiceRequestRevisionReferenceV1?=nil,revision:UInt64,mutationID:MutationIDV1,recordedAt:Date)throws{schemaVersion=Self.schemaVersion;self.recordID=recordID;self.workspaceID=workspaceID;self.submissionPublicID=submissionPublicID;self.invitationPublicID=invitationPublicID;self.source=source;self.scope=scope;self.body=body;self.mediaManifest=mediaManifest;self.acceptedSourceBytes=acceptedSourceBytes;self.capabilityAssessment=capabilityAssessment;self.supersedes=supersedes;self.revision=revision;self.mutationID=mutationID;self.recordedAt=recordedAt;recordSHA256=try ServiceRequestCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,recordID:recordID,workspaceID:workspaceID,submissionPublicID:submissionPublicID,invitationPublicID:invitationPublicID,source:source,scope:scope,body:body,mediaManifest:mediaManifest,acceptedSourceBytes:acceptedSourceBytes,capabilityAssessment:capabilityAssessment,supersedes:supersedes,revision:revision,mutationID:mutationID,recordedAt:recordedAt));try validate()}
    func validate()throws{try ServiceRequestLimitsV1.id(recordID);try scope.validate();try body.validate();try mediaManifest.validate();try acceptedSourceBytes?.validate();try supersedes?.validate();let portable=source == .portableSubmission;guard schemaVersion==Self.schemaVersion,revision>0,(revision==1)==(supersedes==nil),recordedAt.timeIntervalSinceReferenceDate.isFinite,portable==(submissionPublicID != nil),portable==(invitationPublicID != nil),(!portable || acceptedSourceBytes != nil),portable || capabilityAssessment.proofValidity == .unavailable,recordSHA256==(try ServiceRequestCanonicalCodecV1.sha256(basis))else{throw ServiceRequestFailureV1.invalidValue}}
    func validateSuccessor(of p:Self)throws{try p.validate();try validate();guard p.revision<UInt64.max,workspaceID==p.workspaceID,recordID==p.recordID,revision==p.revision+1,supersedes == (try p.reference),source==p.source,scope==p.scope,submissionPublicID==p.submissionPublicID,invitationPublicID==p.invitationPublicID,body==p.body,mediaManifest==p.mediaManifest,acceptedSourceBytes==p.acceptedSourceBytes else{throw ServiceRequestFailureV1.invalidHistory}}
    var reference:ServiceRequestRevisionReferenceV1{get throws{try .init(recordID:recordID,revision:revision,recordSHA256:recordSHA256)}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,recordID:recordID,workspaceID:workspaceID,submissionPublicID:submissionPublicID,invitationPublicID:invitationPublicID,source:source,scope:scope,body:body,mediaManifest:mediaManifest,acceptedSourceBytes:acceptedSourceBytes,capabilityAssessment:capabilityAssessment,supersedes:supersedes,revision:revision,mutationID:mutationID,recordedAt:recordedAt)}
    private struct Basis:Codable{let schemaVersion:Int;let recordID:UUID;let workspaceID:WorkspaceID;let submissionPublicID:ServiceRequestSubmissionPublicIDV1?;let invitationPublicID:ServiceRequestInvitationPublicIDV1?;let source:ServiceRequestSourceKindV1;let scope:ServiceRequestScopeSnapshotV1;let body:ServiceRequestSubmissionBodyV1;let mediaManifest:ServiceRequestMediaManifestV1;let acceptedSourceBytes:CanonicalServiceRequestSourceBytesV1?;let capabilityAssessment:ServiceRequestCapabilityAssessmentV1;let supersedes:ServiceRequestRevisionReferenceV1?;let revision:UInt64;let mutationID:MutationIDV1;let recordedAt:Date}
}

enum ServiceRequestImportDispositionV1:String,Codable,CaseIterable,Hashable,Sendable{case acceptAsNew="ACCEPT_AS_NEW";case acceptAndLinkDuplicate="ACCEPT_AND_LINK_DUPLICATE";case declineWithReason="DECLINE_WITH_REASON";case recordHistoryOnly="RECORD_HISTORY_ONLY";case keepQuarantined="KEEP_QUARANTINED";case discardUnimported="DISCARD_UNIMPORTED"}
enum ServiceRequestStateV1:String,Codable,CaseIterable,Hashable,Sendable{case openUntriaged="OPEN_UNTRIAGED";case openAccepted="OPEN_ACCEPTED";case handledByLinkedWork="HANDLED_BY_LINKED_WORK";case declined="DECLINED";case closedNoWork="CLOSED_NO_WORK";case superseded="SUPERSEDED"}

struct ServiceRequestDispositionEventV1:Codable,Equatable,Hashable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let eventID:UUID;let workspaceID:WorkspaceID;let request:ServiceRequestRevisionReferenceV1;let disposition:ServiceRequestImportDispositionV1;let resultingState:ServiceRequestStateV1;let reason:String?;let duplicateRecord:ServiceRequestRevisionReferenceV1?;let predecessorEventID:UUID?;let predecessorEventSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedAt:Date;let eventSHA256:String
    init(eventID:UUID,workspaceID:WorkspaceID,request:ServiceRequestRevisionReferenceV1,disposition:ServiceRequestImportDispositionV1,resultingState:ServiceRequestStateV1,reason:String?=nil,duplicateRecord:ServiceRequestRevisionReferenceV1?=nil,predecessorEventID:UUID?=nil,predecessorEventSHA256:String?=nil,revision:UInt64,mutationID:MutationIDV1,recordedAt:Date)throws{schemaVersion=Self.schemaVersion;self.eventID=eventID;self.workspaceID=workspaceID;self.request=request;self.disposition=disposition;self.resultingState=resultingState;self.reason=reason;self.duplicateRecord=duplicateRecord;self.predecessorEventID=predecessorEventID;self.predecessorEventSHA256=predecessorEventSHA256;self.revision=revision;self.mutationID=mutationID;self.recordedAt=recordedAt;if let reason{try ServiceRequestLimitsV1.text(reason,maximumBytes:ServiceRequestLimitsV1.maximumReasonBytes)};eventSHA256=try ServiceRequestCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,eventID:eventID,workspaceID:workspaceID,request:request,disposition:disposition,resultingState:resultingState,reason:reason,duplicateRecord:duplicateRecord,predecessorEventID:predecessorEventID,predecessorEventSHA256:predecessorEventSHA256,revision:revision,mutationID:mutationID,recordedAt:recordedAt));try validate()}
    func validate()throws{try ServiceRequestLimitsV1.id(eventID);try request.validate();try duplicateRecord?.validate();if let reason{try ServiceRequestLimitsV1.text(reason,maximumBytes:ServiceRequestLimitsV1.maximumReasonBytes)};if let predecessorEventID{try ServiceRequestLimitsV1.id(predecessorEventID)};if let predecessorEventSHA256{try ServiceRequestLimitsV1.digest(predecessorEventSHA256)};let linked=(disposition == .acceptAndLinkDuplicate)==(duplicateRecord != nil);let expectedState:ServiceRequestStateV1;switch disposition{case .acceptAsNew,.acceptAndLinkDuplicate:expectedState = .openAccepted;case .declineWithReason:expectedState = .declined;case .recordHistoryOnly:expectedState = .closedNoWork;case .keepQuarantined,.discardUnimported:throw ServiceRequestFailureV1.invalidHistory};guard schemaVersion==Self.schemaVersion,revision>0,resultingState==expectedState,(disposition == .declineWithReason)==(reason != nil),(revision==1)==(predecessorEventID==nil),(predecessorEventID==nil)==(predecessorEventSHA256==nil),linked,eventSHA256==(try ServiceRequestCanonicalCodecV1.sha256(basis))else{throw ServiceRequestFailureV1.invalidHistory}}
    func validateSuccessor(of p:Self)throws{try p.validate();try validate();guard p.revision<UInt64.max,workspaceID==p.workspaceID,request.recordID==p.request.recordID,revision==p.revision+1,predecessorEventID==p.eventID,predecessorEventSHA256==p.eventSHA256 else{throw ServiceRequestFailureV1.invalidHistory}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,eventID:eventID,workspaceID:workspaceID,request:request,disposition:disposition,resultingState:resultingState,reason:reason,duplicateRecord:duplicateRecord,predecessorEventID:predecessorEventID,predecessorEventSHA256:predecessorEventSHA256,revision:revision,mutationID:mutationID,recordedAt:recordedAt)};private struct Basis:Codable{let schemaVersion:Int;let eventID:UUID;let workspaceID:WorkspaceID;let request:ServiceRequestRevisionReferenceV1;let disposition:ServiceRequestImportDispositionV1;let resultingState:ServiceRequestStateV1;let reason:String?;let duplicateRecord:ServiceRequestRevisionReferenceV1?;let predecessorEventID:UUID?;let predecessorEventSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedAt:Date}
}

enum ServiceRequestWorkLinkKindV1:String,Codable,CaseIterable,Hashable,Sendable{case link="LINK";case unlinkReversal="UNLINK_REVERSAL"}
enum ServiceRequestWorkChoiceV1:Codable,Equatable,Hashable,Sendable{
    case package(PackageReleaseIdentityV1)
    case activity(activityID:UUID,expectedRevision:UInt64,semanticSHA256:String)
    func validate()throws{switch self{case let .package(value):_ = try PackageReleaseIdentityV1(packageID:value.packageID,schemaVersion:value.schemaVersion,contentVersion:value.contentVersion);case let .activity(id,revision,digest):try ServiceRequestLimitsV1.id(id);try ServiceRequestLimitsV1.digest(digest);guard revision>0 else{throw ServiceRequestFailureV1.invalidValue}}}
}
struct ServiceRequestWorkLinkEventV1:Codable,Equatable,Hashable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let eventID:UUID;let workspaceID:WorkspaceID;let request:ServiceRequestRevisionReferenceV1;let target:WorkSubjectReferenceV1;let choice:ServiceRequestWorkChoiceV1;let canonicalWorkID:UUID;let canonicalWorkRevision:UInt64;let canonicalWorkSHA256:String;let kind:ServiceRequestWorkLinkKindV1;let reversesEventID:UUID?;let predecessorEventID:UUID?;let predecessorEventSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedAt:Date;let eventSHA256:String
    init(eventID:UUID,workspaceID:WorkspaceID,request:ServiceRequestRevisionReferenceV1,target:WorkSubjectReferenceV1,choice:ServiceRequestWorkChoiceV1,canonicalWorkID:UUID,canonicalWorkRevision:UInt64,canonicalWorkSHA256:String,kind:ServiceRequestWorkLinkKindV1,reversesEventID:UUID?=nil,predecessorEventID:UUID?=nil,predecessorEventSHA256:String?=nil,revision:UInt64,mutationID:MutationIDV1,recordedAt:Date)throws{schemaVersion=Self.schemaVersion;self.eventID=eventID;self.workspaceID=workspaceID;self.request=request;self.target=target;self.choice=choice;self.canonicalWorkID=canonicalWorkID;self.canonicalWorkRevision=canonicalWorkRevision;self.canonicalWorkSHA256=canonicalWorkSHA256;self.kind=kind;self.reversesEventID=reversesEventID;self.predecessorEventID=predecessorEventID;self.predecessorEventSHA256=predecessorEventSHA256;self.revision=revision;self.mutationID=mutationID;self.recordedAt=recordedAt;eventSHA256=try ServiceRequestCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,eventID:eventID,workspaceID:workspaceID,request:request,target:target,choice:choice,canonicalWorkID:canonicalWorkID,canonicalWorkRevision:canonicalWorkRevision,canonicalWorkSHA256:canonicalWorkSHA256,kind:kind,reversesEventID:reversesEventID,predecessorEventID:predecessorEventID,predecessorEventSHA256:predecessorEventSHA256,revision:revision,mutationID:mutationID,recordedAt:recordedAt));try validate()}
    func validate()throws{try [eventID,canonicalWorkID].forEach(ServiceRequestLimitsV1.id);try request.validate();try target.validate();try choice.validate();try ServiceRequestLimitsV1.digest(canonicalWorkSHA256);let reversal=(kind == .unlinkReversal)==(reversesEventID != nil);guard schemaVersion==Self.schemaVersion,canonicalWorkRevision>0,revision>0,reversal,(revision==1)==(predecessorEventID==nil),(predecessorEventID==nil)==(predecessorEventSHA256==nil),eventSHA256==(try ServiceRequestCanonicalCodecV1.sha256(basis))else{throw ServiceRequestFailureV1.invalidHistory}}
    func validateSuccessor(of p:Self)throws{try p.validate();try validate();guard p.revision<UInt64.max,workspaceID==p.workspaceID,request==p.request,target==p.target,choice==p.choice,revision==p.revision+1,predecessorEventID==p.eventID,predecessorEventSHA256==p.eventSHA256,kind == .unlinkReversal,reversesEventID==p.eventID,canonicalWorkID==p.canonicalWorkID,canonicalWorkRevision==p.canonicalWorkRevision,canonicalWorkSHA256==p.canonicalWorkSHA256 else{throw ServiceRequestFailureV1.invalidHistory}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,eventID:eventID,workspaceID:workspaceID,request:request,target:target,choice:choice,canonicalWorkID:canonicalWorkID,canonicalWorkRevision:canonicalWorkRevision,canonicalWorkSHA256:canonicalWorkSHA256,kind:kind,reversesEventID:reversesEventID,predecessorEventID:predecessorEventID,predecessorEventSHA256:predecessorEventSHA256,revision:revision,mutationID:mutationID,recordedAt:recordedAt)};private struct Basis:Codable{let schemaVersion:Int;let eventID:UUID;let workspaceID:WorkspaceID;let request:ServiceRequestRevisionReferenceV1;let target:WorkSubjectReferenceV1;let choice:ServiceRequestWorkChoiceV1;let canonicalWorkID:UUID;let canonicalWorkRevision:UInt64;let canonicalWorkSHA256:String;let kind:ServiceRequestWorkLinkKindV1;let reversesEventID:UUID?;let predecessorEventID:UUID?;let predecessorEventSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedAt:Date}
}

enum ServiceRequestDuplicateReasonKindV1:String,Codable,CaseIterable,Hashable,Sendable{case exactCategory="EXACT_CATEGORY";case normalizedTerms="NORMALIZED_TERMS";case boundedTimeWindow="BOUNDED_TIME_WINDOW"}
struct ServiceRequestDuplicateReasonV1:Codable,Equatable,Hashable,Comparable,Sendable{
    let kind:ServiceRequestDuplicateReasonKindV1;let explanation:String;let ruleVersion:Int
    init(kind:ServiceRequestDuplicateReasonKindV1,explanation:String,ruleVersion:Int=1)throws{self.kind=kind;self.explanation=explanation;self.ruleVersion=ruleVersion;try validate()}
    func validate()throws{try ServiceRequestLimitsV1.text(explanation,maximumBytes:ServiceRequestLimitsV1.maximumReasonBytes);guard ruleVersion>0 else{throw ServiceRequestFailureV1.invalidValue}}
    static func <(l:Self,r:Self)->Bool{(l.kind.rawValue,l.explanation,l.ruleVersion)<(r.kind.rawValue,r.explanation,r.ruleVersion)}
    private enum CodingKeys:String,CodingKey,CaseIterable{case kind,explanation,ruleVersion}
    init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(kind:try c.decode(ServiceRequestDuplicateReasonKindV1.self,forKey:.kind),explanation:try c.decode(String.self,forKey:.explanation),ruleVersion:try c.decode(Int.self,forKey:.ruleVersion))}
}
struct ServiceRequestDuplicateCandidateV1:Codable,Equatable,Hashable,Comparable,Sendable{
    let record:ServiceRequestRevisionReferenceV1;let sharedSiteID:UUID;let sharedAssetID:UUID?;let reasons:[ServiceRequestDuplicateReasonV1]
    init(record:ServiceRequestRevisionReferenceV1,sharedSiteID:UUID,sharedAssetID:UUID?=nil,reasons:[ServiceRequestDuplicateReasonV1])throws{self.record=record;self.sharedSiteID=sharedSiteID;self.sharedAssetID=sharedAssetID;self.reasons=reasons.sorted();try validate()}
    func validate()throws{try record.validate();try ServiceRequestLimitsV1.id(sharedSiteID);if let sharedAssetID{try ServiceRequestLimitsV1.id(sharedAssetID)};try reasons.forEach{$0.validate()};guard !reasons.isEmpty,reasons==reasons.sorted(),Set(reasons).count==reasons.count else{throw ServiceRequestFailureV1.invalidValue}}
    static func <(l:Self,r:Self)->Bool{l.record.recordID.uuidString<r.record.recordID.uuidString}
    private enum CodingKeys:String,CodingKey,CaseIterable{case record,sharedSiteID,sharedAssetID,reasons}
    init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireAllowed(decoder,CodingKeys.self,required:[.record,.sharedSiteID,.reasons]);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(record:try c.decode(ServiceRequestRevisionReferenceV1.self,forKey:.record),sharedSiteID:try c.decode(UUID.self,forKey:.sharedSiteID),sharedAssetID:try c.decodeIfPresent(UUID.self,forKey:.sharedAssetID),reasons:try c.decode([ServiceRequestDuplicateReasonV1].self,forKey:.reasons))}
}
struct ServiceRequestDuplicateProjectionV1:Codable,Equatable,Hashable,Sendable{
    let basisRequestSHA256:String;let ruleReleaseSHA256:String;let candidates:[ServiceRequestDuplicateCandidateV1];let suggestionOnly:Bool;let projectionSHA256:String
    init(basisRequestSHA256:String,ruleReleaseSHA256:String,candidates:[ServiceRequestDuplicateCandidateV1])throws{self.basisRequestSHA256=basisRequestSHA256;self.ruleReleaseSHA256=ruleReleaseSHA256;self.candidates=candidates.sorted();suggestionOnly=true;projectionSHA256=try ServiceRequestCanonicalCodecV1.sha256(Basis(basisRequestSHA256:basisRequestSHA256,ruleReleaseSHA256:ruleReleaseSHA256,candidates:self.candidates,suggestionOnly:true));try validate()}
    func validate()throws{try ServiceRequestLimitsV1.digest(basisRequestSHA256);try ServiceRequestLimitsV1.digest(ruleReleaseSHA256);try ServiceRequestLimitsV1.digest(projectionSHA256);try candidates.forEach{$0.validate()};guard suggestionOnly,candidates==candidates.sorted(),candidates.count<=ServiceRequestLimitsV1.maximumDuplicateCandidates,Set(candidates.map{$0.record.recordID}).count==candidates.count,Set(candidates.map(\.sharedSiteID)).count<=1,projectionSHA256==(try ServiceRequestCanonicalCodecV1.sha256(basis))else{throw ServiceRequestFailureV1.limitExceeded}}
    private var basis:Basis{.init(basisRequestSHA256:basisRequestSHA256,ruleReleaseSHA256:ruleReleaseSHA256,candidates:candidates,suggestionOnly:suggestionOnly)}
    private struct Basis:Codable{let basisRequestSHA256:String;let ruleReleaseSHA256:String;let candidates:[ServiceRequestDuplicateCandidateV1];let suggestionOnly:Bool}
    private enum CodingKeys:String,CodingKey,CaseIterable{case basisRequestSHA256,ruleReleaseSHA256,candidates,suggestionOnly,projectionSHA256}
    init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let rebuilt=try Self(basisRequestSHA256:try c.decode(String.self,forKey:.basisRequestSHA256),ruleReleaseSHA256:try c.decode(String.self,forKey:.ruleReleaseSHA256),candidates:try c.decode([ServiceRequestDuplicateCandidateV1].self,forKey:.candidates));guard try c.decode(Bool.self,forKey:.suggestionOnly)==rebuilt.suggestionOnly,try c.decode(String.self,forKey:.projectionSHA256)==rebuilt.projectionSHA256 else{throw ServiceRequestFailureV1.invalidDigest};self=rebuilt}
}

struct ServiceRequestStateProjectionV1:Codable,Equatable,Hashable,Sendable{let request:ServiceRequestRevisionReferenceV1;let state:ServiceRequestStateV1;let latestDispositionEventSHA256:String;let activeWorkLinkEventSHA256:String?;let projectionSHA256:String;init(request:ServiceRequestRevisionReferenceV1,state:ServiceRequestStateV1,latestDispositionEventSHA256:String,activeWorkLinkEventSHA256:String?=nil)throws{try request.validate();try ServiceRequestLimitsV1.digest(latestDispositionEventSHA256);if let activeWorkLinkEventSHA256{try ServiceRequestLimitsV1.digest(activeWorkLinkEventSHA256)};self.request=request;self.state=state;self.latestDispositionEventSHA256=latestDispositionEventSHA256;self.activeWorkLinkEventSHA256=activeWorkLinkEventSHA256;projectionSHA256=try ServiceRequestCanonicalCodecV1.sha256(Basis(request:request,state:state,latestDispositionEventSHA256:latestDispositionEventSHA256,activeWorkLinkEventSHA256:activeWorkLinkEventSHA256));try validate()};func validate()throws{try request.validate();try ServiceRequestLimitsV1.digest(latestDispositionEventSHA256);if let activeWorkLinkEventSHA256{try ServiceRequestLimitsV1.digest(activeWorkLinkEventSHA256)};try ServiceRequestLimitsV1.digest(projectionSHA256);guard (state == .handledByLinkedWork)==(activeWorkLinkEventSHA256 != nil),projectionSHA256==(try ServiceRequestCanonicalCodecV1.sha256(basis))else{throw ServiceRequestFailureV1.invalidDigest}};private var basis:Basis{.init(request:request,state:state,latestDispositionEventSHA256:latestDispositionEventSHA256,activeWorkLinkEventSHA256:activeWorkLinkEventSHA256)};private struct Basis:Codable{let request:ServiceRequestRevisionReferenceV1;let state:ServiceRequestStateV1;let latestDispositionEventSHA256:String;let activeWorkLinkEventSHA256:String?};private enum CodingKeys:String,CodingKey,CaseIterable{case request,state,latestDispositionEventSHA256,activeWorkLinkEventSHA256,projectionSHA256};init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireAllowed(decoder,CodingKeys.self,required:[.request,.state,.latestDispositionEventSHA256,.projectionSHA256]);let c=try decoder.container(keyedBy:CodingKeys.self);let rebuilt=try Self(request:try c.decode(ServiceRequestRevisionReferenceV1.self,forKey:.request),state:try c.decode(ServiceRequestStateV1.self,forKey:.state),latestDispositionEventSHA256:try c.decode(String.self,forKey:.latestDispositionEventSHA256),activeWorkLinkEventSHA256:try c.decodeIfPresent(String.self,forKey:.activeWorkLinkEventSHA256));guard try c.decode(String.self,forKey:.projectionSHA256)==rebuilt.projectionSHA256 else{throw ServiceRequestFailureV1.invalidDigest};self=rebuilt}}

struct ServiceRequestImportPlanV1:Codable,Equatable,Hashable,Sendable{
    let workspaceID:WorkspaceID;let basisWorkspaceRevision:UInt64;let submissionPublicID:ServiceRequestSubmissionPublicIDV1;let canonicalSourceSHA256:String;let capabilityAssessment:ServiceRequestCapabilityAssessmentV1;let duplicateProjection:ServiceRequestDuplicateProjectionV1;let disposition:ServiceRequestImportDispositionV1;let selectedDuplicate:ServiceRequestRevisionReferenceV1?;let mutationID:MutationIDV1;let zeroWrite:Bool;let planSHA256:String
    init(workspaceID:WorkspaceID,basisWorkspaceRevision:UInt64,submissionPublicID:ServiceRequestSubmissionPublicIDV1,canonicalSourceSHA256:String,capabilityAssessment:ServiceRequestCapabilityAssessmentV1,duplicateProjection:ServiceRequestDuplicateProjectionV1,disposition:ServiceRequestImportDispositionV1,selectedDuplicate:ServiceRequestRevisionReferenceV1?=nil,mutationID:MutationIDV1)throws{self.workspaceID=workspaceID;self.basisWorkspaceRevision=basisWorkspaceRevision;self.submissionPublicID=submissionPublicID;self.canonicalSourceSHA256=canonicalSourceSHA256;self.capabilityAssessment=capabilityAssessment;self.duplicateProjection=duplicateProjection;self.disposition=disposition;self.selectedDuplicate=selectedDuplicate;self.mutationID=mutationID;zeroWrite=true;planSHA256=try ServiceRequestCanonicalCodecV1.sha256(Basis(workspaceID:workspaceID,basisWorkspaceRevision:basisWorkspaceRevision,submissionPublicID:submissionPublicID,canonicalSourceSHA256:canonicalSourceSHA256,capabilityAssessment:capabilityAssessment,duplicateProjection:duplicateProjection,disposition:disposition,selectedDuplicate:selectedDuplicate,mutationID:mutationID,zeroWrite:true));try validate()}
    func validate()throws{try submissionPublicID.validate();try ServiceRequestLimitsV1.digest(canonicalSourceSHA256);try ServiceRequestLimitsV1.digest(planSHA256);try duplicateProjection.validate();try selectedDuplicate?.validate();let links=(disposition == .acceptAndLinkDuplicate)==(selectedDuplicate != nil);let selectedExists=selectedDuplicate.map{selected in duplicateProjection.candidates.contains(where:{$0.record==selected})} ?? true;let accepts=disposition == .acceptAsNew || disposition == .acceptAndLinkDuplicate;guard basisWorkspaceRevision>0,zeroWrite,links,selectedExists,duplicateProjection.basisRequestSHA256==canonicalSourceSHA256,(!accepts || (capabilityAssessment.proofValidity == .valid && capabilityAssessment.importEligibility == .eligible)),planSHA256==(try ServiceRequestCanonicalCodecV1.sha256(basis))else{throw ServiceRequestFailureV1.ineligibleImport}}
    private var basis:Basis{.init(workspaceID:workspaceID,basisWorkspaceRevision:basisWorkspaceRevision,submissionPublicID:submissionPublicID,canonicalSourceSHA256:canonicalSourceSHA256,capabilityAssessment:capabilityAssessment,duplicateProjection:duplicateProjection,disposition:disposition,selectedDuplicate:selectedDuplicate,mutationID:mutationID,zeroWrite:zeroWrite)}
    private struct Basis:Codable{let workspaceID:WorkspaceID;let basisWorkspaceRevision:UInt64;let submissionPublicID:ServiceRequestSubmissionPublicIDV1;let canonicalSourceSHA256:String;let capabilityAssessment:ServiceRequestCapabilityAssessmentV1;let duplicateProjection:ServiceRequestDuplicateProjectionV1;let disposition:ServiceRequestImportDispositionV1;let selectedDuplicate:ServiceRequestRevisionReferenceV1?;let mutationID:MutationIDV1;let zeroWrite:Bool}
    private enum CodingKeys:String,CodingKey,CaseIterable{case workspaceID,basisWorkspaceRevision,submissionPublicID,canonicalSourceSHA256,capabilityAssessment,duplicateProjection,disposition,selectedDuplicate,mutationID,zeroWrite,planSHA256}
    init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireAllowed(decoder,CodingKeys.self,required:[.workspaceID,.basisWorkspaceRevision,.submissionPublicID,.canonicalSourceSHA256,.capabilityAssessment,.duplicateProjection,.disposition,.mutationID,.zeroWrite,.planSHA256]);let c=try decoder.container(keyedBy:CodingKeys.self);let rebuilt=try Self(workspaceID:try c.decode(WorkspaceID.self,forKey:.workspaceID),basisWorkspaceRevision:try c.decode(UInt64.self,forKey:.basisWorkspaceRevision),submissionPublicID:try c.decode(ServiceRequestSubmissionPublicIDV1.self,forKey:.submissionPublicID),canonicalSourceSHA256:try c.decode(String.self,forKey:.canonicalSourceSHA256),capabilityAssessment:try c.decode(ServiceRequestCapabilityAssessmentV1.self,forKey:.capabilityAssessment),duplicateProjection:try c.decode(ServiceRequestDuplicateProjectionV1.self,forKey:.duplicateProjection),disposition:try c.decode(ServiceRequestImportDispositionV1.self,forKey:.disposition),selectedDuplicate:try c.decodeIfPresent(ServiceRequestRevisionReferenceV1.self,forKey:.selectedDuplicate),mutationID:try c.decode(MutationIDV1.self,forKey:.mutationID));guard try c.decode(Bool.self,forKey:.zeroWrite)==rebuilt.zeroWrite,try c.decode(String.self,forKey:.planSHA256)==rebuilt.planSHA256 else{throw ServiceRequestFailureV1.invalidDigest};self=rebuilt}
}

struct ServiceRequestImportReceiptV1:Codable,Equatable,Hashable,Sendable{let receiptID:UUID;let workspaceID:WorkspaceID;let submissionPublicID:ServiceRequestSubmissionPublicIDV1;let canonicalSourceSHA256:String;let planSHA256:String;let disposition:ServiceRequestImportDispositionV1;let mutationID:MutationIDV1;let canonicalMutationReceiptSHA256:String?;let resultingRecord:ServiceRequestRevisionReferenceV1?;let recordedAt:Date;let receiptSHA256:String;init(receiptID:UUID,workspaceID:WorkspaceID,submissionPublicID:ServiceRequestSubmissionPublicIDV1,canonicalSourceSHA256:String,planSHA256:String,disposition:ServiceRequestImportDispositionV1,mutationID:MutationIDV1,canonicalMutationReceiptSHA256:String?=nil,resultingRecord:ServiceRequestRevisionReferenceV1?=nil,recordedAt:Date)throws{try ServiceRequestLimitsV1.id(receiptID);try submissionPublicID.validate();try [canonicalSourceSHA256,planSHA256].forEach(ServiceRequestLimitsV1.digest);if let canonicalMutationReceiptSHA256{try ServiceRequestLimitsV1.digest(canonicalMutationReceiptSHA256)};try resultingRecord?.validate();let canonical=[ServiceRequestImportDispositionV1.acceptAsNew,.acceptAndLinkDuplicate,.declineWithReason,.recordHistoryOnly].contains(disposition);guard canonical==(canonicalMutationReceiptSHA256 != nil),canonical==(resultingRecord != nil),recordedAt.timeIntervalSinceReferenceDate.isFinite else{throw ServiceRequestFailureV1.invalidValue};self.receiptID=receiptID;self.workspaceID=workspaceID;self.submissionPublicID=submissionPublicID;self.canonicalSourceSHA256=canonicalSourceSHA256;self.planSHA256=planSHA256;self.disposition=disposition;self.mutationID=mutationID;self.canonicalMutationReceiptSHA256=canonicalMutationReceiptSHA256;self.resultingRecord=resultingRecord;self.recordedAt=recordedAt;receiptSHA256=try ServiceRequestCanonicalCodecV1.sha256(Basis(receiptID:receiptID,workspaceID:workspaceID,submissionPublicID:submissionPublicID,canonicalSourceSHA256:canonicalSourceSHA256,planSHA256:planSHA256,disposition:disposition,mutationID:mutationID,canonicalMutationReceiptSHA256:canonicalMutationReceiptSHA256,resultingRecord:resultingRecord,recordedAt:recordedAt));try validate()};func validate()throws{try ServiceRequestLimitsV1.id(receiptID);try submissionPublicID.validate();try [canonicalSourceSHA256,planSHA256,receiptSHA256].forEach(ServiceRequestLimitsV1.digest);if let canonicalMutationReceiptSHA256{try ServiceRequestLimitsV1.digest(canonicalMutationReceiptSHA256)};try resultingRecord?.validate();let canonical=[ServiceRequestImportDispositionV1.acceptAsNew,.acceptAndLinkDuplicate,.declineWithReason,.recordHistoryOnly].contains(disposition);guard canonical==(canonicalMutationReceiptSHA256 != nil),canonical==(resultingRecord != nil),recordedAt.timeIntervalSinceReferenceDate.isFinite,receiptSHA256==(try ServiceRequestCanonicalCodecV1.sha256(basis))else{throw ServiceRequestFailureV1.invalidHistory}};private var basis:Basis{.init(receiptID:receiptID,workspaceID:workspaceID,submissionPublicID:submissionPublicID,canonicalSourceSHA256:canonicalSourceSHA256,planSHA256:planSHA256,disposition:disposition,mutationID:mutationID,canonicalMutationReceiptSHA256:canonicalMutationReceiptSHA256,resultingRecord:resultingRecord,recordedAt:recordedAt)};private struct Basis:Codable{let receiptID:UUID;let workspaceID:WorkspaceID;let submissionPublicID:ServiceRequestSubmissionPublicIDV1;let canonicalSourceSHA256:String;let planSHA256:String;let disposition:ServiceRequestImportDispositionV1;let mutationID:MutationIDV1;let canonicalMutationReceiptSHA256:String?;let resultingRecord:ServiceRequestRevisionReferenceV1?;let recordedAt:Date};private enum CodingKeys:String,CodingKey,CaseIterable{case receiptID,workspaceID,submissionPublicID,canonicalSourceSHA256,planSHA256,disposition,mutationID,canonicalMutationReceiptSHA256,resultingRecord,recordedAt,receiptSHA256};init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireAllowed(decoder,CodingKeys.self,required:[.receiptID,.workspaceID,.submissionPublicID,.canonicalSourceSHA256,.planSHA256,.disposition,.mutationID,.recordedAt,.receiptSHA256]);let c=try decoder.container(keyedBy:CodingKeys.self);let rebuilt=try Self(receiptID:try c.decode(UUID.self,forKey:.receiptID),workspaceID:try c.decode(WorkspaceID.self,forKey:.workspaceID),submissionPublicID:try c.decode(ServiceRequestSubmissionPublicIDV1.self,forKey:.submissionPublicID),canonicalSourceSHA256:try c.decode(String.self,forKey:.canonicalSourceSHA256),planSHA256:try c.decode(String.self,forKey:.planSHA256),disposition:try c.decode(ServiceRequestImportDispositionV1.self,forKey:.disposition),mutationID:try c.decode(MutationIDV1.self,forKey:.mutationID),canonicalMutationReceiptSHA256:try c.decodeIfPresent(String.self,forKey:.canonicalMutationReceiptSHA256),resultingRecord:try c.decodeIfPresent(ServiceRequestRevisionReferenceV1.self,forKey:.resultingRecord),recordedAt:try c.decode(Date.self,forKey:.recordedAt));guard try c.decode(String.self,forKey:.receiptSHA256)==rebuilt.receiptSHA256 else{throw ServiceRequestFailureV1.invalidDigest};self=rebuilt}}

enum ServiceRequestMutationPayloadV1:Codable,Equatable,Hashable,Sendable{case appendRecord(ServiceRequestRecordV1);case appendDisposition(ServiceRequestDispositionEventV1);case appendWorkLink(ServiceRequestWorkLinkEventV1);case appendWorkLinkReversal(ServiceRequestWorkLinkEventV1)}
struct ServiceRequestMutationV1:Codable,Equatable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let workspaceID:WorkspaceID;let expectedRevision:WorkspaceExpectedRevisionV1;let mutationID:MutationIDV1;let payloads:[ServiceRequestMutationPayloadV1];init(workspaceID:WorkspaceID,expectedRevision:WorkspaceExpectedRevisionV1,mutationID:MutationIDV1,payloads:[ServiceRequestMutationPayloadV1])throws{guard !payloads.isEmpty,payloads.count<=ServiceRequestLimitsV1.maximumRecordsPerMutation else{throw ServiceRequestFailureV1.limitExceeded};schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID;self.expectedRevision=expectedRevision;self.mutationID=mutationID;self.payloads=payloads;try validate()};func validate()throws{guard schemaVersion==Self.schemaVersion,expectedRevision.workspaceID==workspaceID,!payloads.isEmpty,payloads.count<=ServiceRequestLimitsV1.maximumRecordsPerMutation else{throw ServiceRequestFailureV1.incompatibleVersion};for payload in payloads{switch payload{case let .appendRecord(v):try v.validate();guard v.workspaceID==workspaceID,v.mutationID==mutationID else{throw ServiceRequestFailureV1.scopeMismatch};case let .appendDisposition(v):try v.validate();guard v.workspaceID==workspaceID,v.mutationID==mutationID else{throw ServiceRequestFailureV1.scopeMismatch};case let .appendWorkLink(v):try v.validate();guard v.workspaceID==workspaceID,v.mutationID==mutationID,v.kind == .link else{throw ServiceRequestFailureV1.scopeMismatch};case let .appendWorkLinkReversal(v):try v.validate();guard v.workspaceID==workspaceID,v.mutationID==mutationID,v.kind == .unlinkReversal else{throw ServiceRequestFailureV1.scopeMismatch}}}};private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,workspaceID,expectedRevision,mutationID,payloads};init(from decoder:Decoder)throws{try ServiceRequestClosedCodingV1.requireExact(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let rebuilt=try Self(workspaceID:try c.decode(WorkspaceID.self,forKey:.workspaceID),expectedRevision:try c.decode(WorkspaceExpectedRevisionV1.self,forKey:.expectedRevision),mutationID:try c.decode(MutationIDV1.self,forKey:.mutationID),payloads:try c.decode([ServiceRequestMutationPayloadV1].self,forKey:.payloads));guard try c.decode(Int.self,forKey:.schemaVersion)==rebuilt.schemaVersion else{throw ServiceRequestFailureV1.incompatibleVersion};self=rebuilt}}

enum ServiceRequestNoncanonicalBoundaryV1 {
    static let duplicateProjectionIsPersistent = false
    static let stateProjectionIsPersistent = false
    static let importPlanIsPersistent = false
    static let rawCapabilityIsWorkspaceTruth = false
    static let stagingOwnsCanonicalRequestTruth = false
    static let previewWritesWorkspace = false
    static let automaticWorkCreationPermitted = false
    static let automaticDuplicateMergePermitted = false
}

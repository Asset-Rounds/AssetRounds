import Foundation

enum ContentContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case limitExceeded
    case unknownAlgorithm
    case duplicateIdentity
    case wrongWorkspace
    case staleReference
    case missingContent
    case orphanEvidence
    case immutableOriginal
    case digestMismatch
    case byteLengthMismatch
    case mediaTypeMismatch
    case invalidProvenance
    case cycleDetected
    case historyRewrite
    case incompatibleVersion
}

enum FieldReferenceContentBoundaryV1 {
    static func validateImmutableOriginals(_ references: [ContentReferenceV1], workspaceID: WorkspaceID) throws {
        let expected = workspaceID.rawValue.uuidString.lowercased()
        guard !references.isEmpty,
              Set(references.map(\.contentID)).count == references.count,
              references.allSatisfy({ $0.workspaceID == expected && $0.byteRole == .immutableOriginal }) else {
            throw ContentContractFailureV1.immutableOriginal
        }
    }
}

enum ContentContractLimitsV1 {
    static let maximumIDBytes = 128
    static let maximumMediaTypeBytes = 127
    static let maximumDigestCount = 2
    static let maximumManifestEntries = 256
    static let maximumAssociations = 512
    static let maximumProvenanceSources = 32
    static let maximumTextBytes = 1_024
    static let maximumCanonicalBytes = 1_048_576
}

enum ContentContractValidationV1 {
    static func validID(_ value: String) -> Bool {
        WorkflowGrammarValidationV1.validID(value)
    }

    static func validMediaType(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= ContentContractLimitsV1.maximumMediaTypeBytes,
              value == value.lowercased(),
              value.filter({ $0 == "/" }).count == 1,
              let slash = value.firstIndex(of: "/"), slash != value.startIndex,
              value.index(after: slash) != value.endIndex else { return false }
        return value.utf8.allSatisfy {
            (0x61...0x7A).contains($0) || (0x30...0x39).contains($0)
                || $0 == 0x2F || $0 == 0x2B || $0 == 0x2D || $0 == 0x2E
        }
    }

    static func validVersion(_ value: String) -> Bool {
        validID(value)
    }
}

enum ContentDigestAlgorithmV1: String, CaseIterable, Codable, Hashable, Sendable {
    case sha256 = "SHA256"
    case sha512 = "SHA512"

    var hexadecimalLength: Int {
        switch self {
        case .sha256: return 64
        case .sha512: return 128
        }
    }
}

struct ContentDigestV1: Codable, Equatable, Hashable, Sendable {
    let algorithm: ContentDigestAlgorithmV1
    let hexadecimalValue: String

    init(algorithm: ContentDigestAlgorithmV1, hexadecimalValue: String) throws {
        guard hexadecimalValue.count == algorithm.hexadecimalLength,
              hexadecimalValue.utf8.allSatisfy({
                (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
              }) else { throw ContentContractFailureV1.invalidValue }
        self.algorithm = algorithm
        self.hexadecimalValue = hexadecimalValue
    }
}

struct ContentDigestSetV1: Codable, Equatable, Hashable, Sendable {
    let values: [ContentDigestV1]

    init(_ values: [ContentDigestV1]) throws {
        let sorted = values.sorted { $0.algorithm.rawValue < $1.algorithm.rawValue }
        guard !sorted.isEmpty,
              sorted.count <= ContentContractLimitsV1.maximumDigestCount,
              sorted == values,
              Set(sorted.map(\.algorithm)).count == sorted.count,
              sorted.contains(where: { $0.algorithm == .sha256 }) else {
            throw ContentContractFailureV1.invalidValue
        }
        self.values = sorted
    }

    func digest(for algorithm: ContentDigestAlgorithmV1) -> ContentDigestV1? {
        values.first { $0.algorithm == algorithm }
    }
}

enum ContentByteRoleV1: String, CaseIterable, Codable, Hashable, Sendable {
    case immutableOriginal = "IMMUTABLE_ORIGINAL"
    case derivative = "DERIVATIVE"
}

struct ContentReferenceV1: Codable, Equatable, Hashable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: String
    let contentID: String
    let byteLength: Int64
    let mediaType: String
    let digests: ContentDigestSetV1
    let byteRole: ContentByteRoleV1
    let createdAt: String

    var id: String { "\(workspaceID)|\(contentID)" }

    init(
        workspaceID: String,
        contentID: String,
        byteLength: Int64,
        mediaType: String,
        digests: ContentDigestSetV1,
        byteRole: ContentByteRoleV1,
        createdAt: String
    ) throws {
        guard ContentContractValidationV1.validID(workspaceID),
              ContentContractValidationV1.validID(contentID), byteLength >= 0,
              ContentContractValidationV1.validMediaType(mediaType),
              FindingContractValidationV1.validInstant(createdAt) else {
            throw ContentContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.contentID = contentID
        self.byteLength = byteLength
        self.mediaType = mediaType
        self.digests = digests
        self.byteRole = byteRole
        self.createdAt = createdAt
    }

    func validateImmutableIdentity(against other: ContentReferenceV1) throws {
        guard workspaceID == other.workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
        guard contentID == other.contentID else { throw ContentContractFailureV1.missingContent }
        guard self == other else { throw ContentContractFailureV1.immutableOriginal }
    }
}

enum ContentClosedCodingV1 {
    static func requireExact(_ decoder: any Decoder, keys: [String]) throws {
        try KernelClosedCodingV1.require(decoder, keys: keys)
    }

    static func requireClosed(_ decoder: any Decoder, allowed: [String], required: [String]) throws {
        try KernelClosedCodingV1.require(decoder, keys: allowed, required: required)
    }
}

extension ContentDigestV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case algorithm, hexadecimalValue }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawAlgorithm = try c.decode(String.self, forKey: .algorithm)
        guard let algorithm = ContentDigestAlgorithmV1(rawValue: rawAlgorithm) else {
            throw ContentContractFailureV1.unknownAlgorithm
        }
        try self.init(
            algorithm: algorithm,
            hexadecimalValue: c.decode(String.self, forKey: .hexadecimalValue)
        )
    }
}

extension ContentDigestSetV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case values }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(c.decode([ContentDigestV1].self, forKey: .values))
    }
}

extension ContentReferenceV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, contentID, byteLength, mediaType, digests, byteRole, createdAt
    }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw ContentContractFailureV1.incompatibleVersion
        }
        try self.init(
            workspaceID: c.decode(String.self, forKey: .workspaceID),
            contentID: c.decode(String.self, forKey: .contentID),
            byteLength: c.decode(Int64.self, forKey: .byteLength),
            mediaType: c.decode(String.self, forKey: .mediaType),
            digests: c.decode(ContentDigestSetV1.self, forKey: .digests),
            byteRole: c.decode(ContentByteRoleV1.self, forKey: .byteRole),
            createdAt: c.decode(String.self, forKey: .createdAt)
        )
    }
}

extension ContentReferenceV1 {
    /// Privacy processing never changes the original identity. A rendered
    /// result is required to be a distinct derivative with its own digest.
    func validatePrivacyDerivative(_ derivative: ContentReferenceV1) throws {
        guard byteRole == .immutableOriginal,
              derivative.byteRole == .derivative,
              workspaceID == derivative.workspaceID,
              contentID != derivative.contentID,
              digests.digest(for: .sha256) != derivative.digests.digest(for: .sha256) else {
            throw ContentContractFailureV1.immutableOriginal
        }
    }
}

extension ContentReferenceV1 {
    func validateAuthoritySourceBinding(_ release: AuthoritySourceReleaseV1) throws {
        try release.validate()
        guard release.licenseStorageDisposition == .lawfulContentReference,
              release.lawfulContentReference == self,
              AuthorityCriterionValidationV1.sameWorkspaceString(
                workspaceID,
                as: release.workspaceID
              ) else {
            throw ContentContractFailureV1.wrongWorkspace
        }
    }
}

// MARK: - C24 accessible-document audience boundary

/// Accessible-document semantic trees are derived report companions.  This
/// boundary validates the canonical tree while making the customer-safe
/// audience requirement explicit; it never turns a content reference into a
/// searchable node, locator, or alternate source of truth.
enum AccessibleDocumentContentReferenceBoundaryV1 {
    static let semanticTreeIsDerivedOnly = true
    static let requiresCustomerSafeAudience = true
    static let excludesOriginalBytes = true
    static let excludesPrivateEvidence = true
    static let excludesLocators = true
    static let excludesAssessorIdentity = true

    static func validateAudienceSafeTree(
        _ tree: AccessibleDocumentSemanticTreeV1
    ) throws {
        try tree.validate()
        guard tree.audience == .customerSafe,
              tree.nodes.allSatisfy({ $0.sensitivity == .customerSafe }) else {
            throw AccessibleDocumentFailureV1.privacyViolation
        }
    }

    static func validateAssessment(
        _ assessment: AccessibleDocumentAssessmentReceiptV1,
        for tree: AccessibleDocumentSemanticTreeV1
    ) throws {
        try validateAudienceSafeTree(tree)
        try assessment.validate(tree: tree)
    }
}

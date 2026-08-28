import Foundation

enum OriginalContentOriginV1: String, CaseIterable, Codable, Hashable, Sendable {
    case humanCapture = "HUMAN_CAPTURE"
    case localImport = "LOCAL_IMPORT"
}

struct ContentOriginalProvenanceV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let provenanceID: String
    let workspaceID: String
    let contentID: String
    let contentDigest: ContentDigestV1
    let origin: OriginalContentOriginV1
    let recordedAt: String

    var id: String { "\(workspaceID)|\(provenanceID)" }

    init(
        provenanceID: String,
        workspaceID: String,
        contentID: String,
        contentDigest: ContentDigestV1,
        origin: OriginalContentOriginV1,
        recordedAt: String
    ) throws {
        guard [provenanceID, workspaceID, contentID].allSatisfy(ContentContractValidationV1.validID),
              FindingContractValidationV1.validInstant(recordedAt) else {
            throw ContentContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.provenanceID = provenanceID
        self.workspaceID = workspaceID
        self.contentID = contentID
        self.contentDigest = contentDigest
        self.origin = origin
        self.recordedAt = recordedAt
    }
}

struct ContentSourceBindingV1: Codable, Equatable, Hashable, Sendable {
    let contentID: String
    let digest: ContentDigestV1

    init(contentID: String, digest: ContentDigestV1) throws {
        guard ContentContractValidationV1.validID(contentID) else { throw ContentContractFailureV1.invalidValue }
        self.contentID = contentID
        self.digest = digest
    }
}

struct SanitizedDerivativeV1: Codable, Equatable, Sendable {
    let sanitizerID: String
    let sanitizerVersion: String

    init(sanitizerID: String, sanitizerVersion: String) throws {
        guard ContentContractValidationV1.validID(sanitizerID), ContentContractValidationV1.validVersion(sanitizerVersion) else {
            throw ContentContractFailureV1.invalidValue
        }
        self.sanitizerID = sanitizerID; self.sanitizerVersion = sanitizerVersion
    }
}

struct ThumbnailDerivativeV1: Codable, Equatable, Sendable {
    let rendererID: String
    let rendererVersion: String
    let pixelWidth: Int
    let pixelHeight: Int

    init(rendererID: String, rendererVersion: String, pixelWidth: Int, pixelHeight: Int) throws {
        guard ContentContractValidationV1.validID(rendererID), ContentContractValidationV1.validVersion(rendererVersion),
              (1...16_384).contains(pixelWidth), (1...16_384).contains(pixelHeight) else {
            throw ContentContractFailureV1.invalidValue
        }
        self.rendererID = rendererID; self.rendererVersion = rendererVersion
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
    }
}

struct AnnotationDerivativeV1: Codable, Equatable, Sendable {
    let rendererID: String
    let rendererVersion: String
    let annotationManifestSHA256: String

    init(rendererID: String, rendererVersion: String, annotationManifestSHA256: String) throws {
        guard ContentContractValidationV1.validID(rendererID), ContentContractValidationV1.validVersion(rendererVersion),
              KernelCanonicalHashV1.validSHA256(annotationManifestSHA256) else {
            throw ContentContractFailureV1.invalidValue
        }
        self.rendererID = rendererID; self.rendererVersion = rendererVersion
        self.annotationManifestSHA256 = annotationManifestSHA256
    }
}

struct SequenceDerivativeV1: Codable, Equatable, Sendable {
    let assemblerID: String
    let assemblerVersion: String
    let orderedSourceCount: Int

    init(assemblerID: String, assemblerVersion: String, orderedSourceCount: Int) throws {
        guard ContentContractValidationV1.validID(assemblerID), ContentContractValidationV1.validVersion(assemblerVersion),
              (1...ContentContractLimitsV1.maximumProvenanceSources).contains(orderedSourceCount) else {
            throw ContentContractFailureV1.invalidValue
        }
        self.assemblerID = assemblerID; self.assemblerVersion = assemblerVersion
        self.orderedSourceCount = orderedSourceCount
    }
}

struct PrivacyDerivativeV1: Codable, Equatable, Sendable {
    let privacyManifestID: UUID
    let privacyManifestSHA256: String
    let rendererID: String
    let rendererVersion: String

    init(privacyManifestID: UUID, privacyManifestSHA256: String, rendererID: String, rendererVersion: String) throws {
        guard KernelCanonicalHashV1.validSHA256(privacyManifestSHA256),
              ContentContractValidationV1.validID(rendererID),
              ContentContractValidationV1.validVersion(rendererVersion) else {
            throw ContentContractFailureV1.invalidProvenance
        }
        self.privacyManifestID = privacyManifestID; self.privacyManifestSHA256 = privacyManifestSHA256
        self.rendererID = rendererID; self.rendererVersion = rendererVersion
    }
}

enum ContentDerivativeTransformV1: Codable, Equatable, Sendable {
    case sanitized(SanitizedDerivativeV1)
    case thumbnail(ThumbnailDerivativeV1)
    case annotation(AnnotationDerivativeV1)
    case sequence(SequenceDerivativeV1)
    case privacy(PrivacyDerivativeV1)

    var kind: String {
        switch self {
        case .sanitized: return "SANITIZED"
        case .thumbnail: return "THUMBNAIL"
        case .annotation: return "ANNOTATION"
        case .sequence: return "SEQUENCE"
        case .privacy: return "PRIVACY"
        }
    }
}

struct ContentDerivativeProvenanceV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let provenanceID: String
    let workspaceID: String
    let sources: [ContentSourceBindingV1]
    let derivativeContentID: String
    let derivativeDigest: ContentDigestV1
    let transform: ContentDerivativeTransformV1
    let metadataSanitizerID: String
    let metadataSanitizerVersion: String
    let createdAt: String

    var id: String { "\(workspaceID)|\(provenanceID)" }

    init(
        provenanceID: String,
        workspaceID: String,
        sources: [ContentSourceBindingV1],
        derivativeContentID: String,
        derivativeDigest: ContentDigestV1,
        transform: ContentDerivativeTransformV1,
        metadataSanitizerID: String,
        metadataSanitizerVersion: String,
        createdAt: String
    ) throws {
        guard [provenanceID, workspaceID, derivativeContentID].allSatisfy(ContentContractValidationV1.validID),
              !sources.isEmpty, sources.count <= ContentContractLimitsV1.maximumProvenanceSources,
              Set(sources.map(\.contentID)).count == sources.count,
              !sources.contains(where: { $0.contentID == derivativeContentID }),
              ContentContractValidationV1.validID(metadataSanitizerID),
              ContentContractValidationV1.validVersion(metadataSanitizerVersion),
              FindingContractValidationV1.validInstant(createdAt) else {
            throw ContentContractFailureV1.invalidProvenance
        }
        switch transform {
        case .sequence(let sequence):
            guard sequence.orderedSourceCount == sources.count else { throw ContentContractFailureV1.invalidProvenance }
        case .privacy:
            guard sources.count == 1 else { throw ContentContractFailureV1.invalidProvenance }
        default:
            guard sources.count == 1 else { throw ContentContractFailureV1.invalidProvenance }
        }
        schemaVersion = Self.schemaVersion
        self.provenanceID = provenanceID; self.workspaceID = workspaceID; self.sources = sources
        self.derivativeContentID = derivativeContentID; self.derivativeDigest = derivativeDigest
        self.transform = transform; self.metadataSanitizerID = metadataSanitizerID
        self.metadataSanitizerVersion = metadataSanitizerVersion; self.createdAt = createdAt
    }
}

enum ContentProvenanceGraphV1 {
    // IMMUTABLE_ORIGINAL references require one exact original-provenance row.
    static func validate(
        references: [ContentReferenceV1],
        originals: [ContentOriginalProvenanceV1],
        derivatives: [ContentDerivativeProvenanceV1]
    ) throws {
        guard references.count <= ContentContractLimitsV1.maximumManifestEntries,
              originals.count <= ContentContractLimitsV1.maximumManifestEntries,
              derivatives.count <= ContentContractLimitsV1.maximumManifestEntries else {
            throw ContentContractFailureV1.limitExceeded
        }
        let referenceKeys = references.map { "\($0.workspaceID)|\($0.contentID)" }
        let originalKeys = originals.map { "\($0.workspaceID)|\($0.contentID)" }
        let derivativeKeys = derivatives.map { "\($0.workspaceID)|\($0.derivativeContentID)" }
        let provenanceKeys = originals.map { "\($0.workspaceID)|\($0.provenanceID)" }
            + derivatives.map { "\($0.workspaceID)|\($0.provenanceID)" }
        guard Set(referenceKeys).count == references.count,
              Set(originalKeys).count == originals.count,
              Set(derivativeKeys).count == derivatives.count,
              Set(provenanceKeys).count == provenanceKeys.count else {
            throw ContentContractFailureV1.duplicateIdentity
        }
        let byID = Dictionary(uniqueKeysWithValues: references.map {
            ("\($0.workspaceID)|\($0.contentID)", $0)
        })
        for original in originals {
            guard let reference = byID["\(original.workspaceID)|\(original.contentID)"] else { throw ContentContractFailureV1.missingContent }
            guard reference.workspaceID == original.workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
            guard reference.byteRole == .immutableOriginal else { throw ContentContractFailureV1.immutableOriginal }
            guard reference.digests.digest(for: original.contentDigest.algorithm) == original.contentDigest else {
                throw ContentContractFailureV1.digestMismatch
            }
        }
        var edges: [String: [String]] = [:]
        for derivative in derivatives {
            let targetKey = "\(derivative.workspaceID)|\(derivative.derivativeContentID)"
            guard let target = byID[targetKey] else { throw ContentContractFailureV1.missingContent }
            guard target.workspaceID == derivative.workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
            guard target.byteRole == .derivative else { throw ContentContractFailureV1.immutableOriginal }
            guard target.digests.digest(for: derivative.derivativeDigest.algorithm) == derivative.derivativeDigest else {
                throw ContentContractFailureV1.digestMismatch
            }
            for source in derivative.sources {
                let sourceKey = "\(derivative.workspaceID)|\(source.contentID)"
                guard let sourceReference = byID[sourceKey] else { throw ContentContractFailureV1.missingContent }
                guard sourceReference.workspaceID == derivative.workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
                guard sourceReference.digests.digest(for: source.digest.algorithm) == source.digest else {
                    throw ContentContractFailureV1.digestMismatch
                }
                edges[sourceKey, default: []].append(targetKey)
            }
        }
        let originalIDs = Set(originalKeys)
        let derivativeIDs = Set(derivativeKeys)
        for reference in references {
            let key = "\(reference.workspaceID)|\(reference.contentID)"
            switch reference.byteRole {
            case .immutableOriginal:
                guard originalIDs.contains(key), !derivativeIDs.contains(key) else {
                    throw ContentContractFailureV1.invalidProvenance
                }
            case .derivative:
                guard derivativeIDs.contains(key), !originalIDs.contains(key) else {
                    throw ContentContractFailureV1.invalidProvenance
                }
            }
        }
        var visiting = Set<String>(), visited = Set<String>()
        func visit(_ id: String) throws {
            if visiting.contains(id) { throw ContentContractFailureV1.cycleDetected }
            if visited.contains(id) { return }
            visiting.insert(id)
            for next in (edges[id] ?? []).sorted() { try visit(next) }
            visiting.remove(id); visited.insert(id)
        }
        for id in edges.keys.sorted() { try visit(id) }
    }
}

// Strict tagged coding prevents an unknown derivative kind from being treated as an original.
extension ContentDerivativeTransformV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case kind, sanitized, thumbnail, annotation, sequence, privacy }
    init(from decoder: any Decoder) throws {
        let raw = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .kind)
        switch raw {
        case "SANITIZED":
            try ContentClosedCodingV1.requireExact(decoder, keys: ["kind", "sanitized"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self = .sanitized(try c.decode(SanitizedDerivativeV1.self, forKey: .sanitized))
        case "THUMBNAIL":
            try ContentClosedCodingV1.requireExact(decoder, keys: ["kind", "thumbnail"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self = .thumbnail(try c.decode(ThumbnailDerivativeV1.self, forKey: .thumbnail))
        case "ANNOTATION":
            try ContentClosedCodingV1.requireExact(decoder, keys: ["kind", "annotation"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self = .annotation(try c.decode(AnnotationDerivativeV1.self, forKey: .annotation))
        case "SEQUENCE":
            try ContentClosedCodingV1.requireExact(decoder, keys: ["kind", "sequence"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self = .sequence(try c.decode(SequenceDerivativeV1.self, forKey: .sequence))
        case "PRIVACY":
            try ContentClosedCodingV1.requireExact(decoder, keys: ["kind", "privacy"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self = .privacy(try c.decode(PrivacyDerivativeV1.self, forKey: .privacy))
        default: throw ContentContractFailureV1.invalidProvenance
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .sanitized(let value): try c.encode(value, forKey: .sanitized)
        case .thumbnail(let value): try c.encode(value, forKey: .thumbnail)
        case .annotation(let value): try c.encode(value, forKey: .annotation)
        case .sequence(let value): try c.encode(value, forKey: .sequence)
        case .privacy(let value): try c.encode(value, forKey: .privacy)
        }
    }
}

extension ContentOriginalProvenanceV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, provenanceID, workspaceID, contentID, contentDigest, origin, recordedAt }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ContentContractFailureV1.incompatibleVersion }
        try self.init(provenanceID: c.decode(String.self, forKey: .provenanceID), workspaceID: c.decode(String.self, forKey: .workspaceID), contentID: c.decode(String.self, forKey: .contentID), contentDigest: c.decode(ContentDigestV1.self, forKey: .contentDigest), origin: c.decode(OriginalContentOriginV1.self, forKey: .origin), recordedAt: c.decode(String.self, forKey: .recordedAt))
    }
}

extension ContentSourceBindingV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case contentID, digest }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(contentID: c.decode(String.self, forKey: .contentID), digest: c.decode(ContentDigestV1.self, forKey: .digest))
    }
}

extension SanitizedDerivativeV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case sanitizerID, sanitizerVersion }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(sanitizerID: c.decode(String.self, forKey: .sanitizerID), sanitizerVersion: c.decode(String.self, forKey: .sanitizerVersion))
    }
}

extension ThumbnailDerivativeV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case rendererID, rendererVersion, pixelWidth, pixelHeight }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(rendererID: c.decode(String.self, forKey: .rendererID), rendererVersion: c.decode(String.self, forKey: .rendererVersion), pixelWidth: c.decode(Int.self, forKey: .pixelWidth), pixelHeight: c.decode(Int.self, forKey: .pixelHeight))
    }
}

extension AnnotationDerivativeV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case rendererID, rendererVersion, annotationManifestSHA256 }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(rendererID: c.decode(String.self, forKey: .rendererID), rendererVersion: c.decode(String.self, forKey: .rendererVersion), annotationManifestSHA256: c.decode(String.self, forKey: .annotationManifestSHA256))
    }
}

extension SequenceDerivativeV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case assemblerID, assemblerVersion, orderedSourceCount }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(assemblerID: c.decode(String.self, forKey: .assemblerID), assemblerVersion: c.decode(String.self, forKey: .assemblerVersion), orderedSourceCount: c.decode(Int.self, forKey: .orderedSourceCount))
    }
}

extension PrivacyDerivativeV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case privacyManifestID, privacyManifestSHA256, rendererID, rendererVersion }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(privacyManifestID: c.decode(UUID.self, forKey: .privacyManifestID), privacyManifestSHA256: c.decode(String.self, forKey: .privacyManifestSHA256), rendererID: c.decode(String.self, forKey: .rendererID), rendererVersion: c.decode(String.self, forKey: .rendererVersion))
    }
}

extension ContentDerivativeProvenanceV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, provenanceID, workspaceID, sources, derivativeContentID, derivativeDigest, transform, metadataSanitizerID, metadataSanitizerVersion, createdAt }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ContentContractFailureV1.incompatibleVersion }
        try self.init(provenanceID: c.decode(String.self, forKey: .provenanceID), workspaceID: c.decode(String.self, forKey: .workspaceID), sources: c.decode([ContentSourceBindingV1].self, forKey: .sources), derivativeContentID: c.decode(String.self, forKey: .derivativeContentID), derivativeDigest: c.decode(ContentDigestV1.self, forKey: .derivativeDigest), transform: c.decode(ContentDerivativeTransformV1.self, forKey: .transform), metadataSanitizerID: c.decode(String.self, forKey: .metadataSanitizerID), metadataSanitizerVersion: c.decode(String.self, forKey: .metadataSanitizerVersion), createdAt: c.decode(String.self, forKey: .createdAt))
    }
}

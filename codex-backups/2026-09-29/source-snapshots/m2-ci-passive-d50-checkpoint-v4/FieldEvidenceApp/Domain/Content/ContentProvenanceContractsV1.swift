import Foundation

enum ScheduleContentProvenanceBoundaryV1 { static let dueStateIsAuthorityClaim = false }

enum C51ScheduleContentProvenanceBoundaryV1 {
    static let scheduleProvenanceIsContentProvenance = false
    static let scheduleCarriesNoCaptureOrImportProvenance = true
    static let canonicalContentProvenanceOwnerRemainsUnchanged = true
}

enum AssetLocatorProvenanceBoundaryV1 {
    static let signedPayloadProvesAuthorship = false
    static let signedPayloadProvesAuthorization = false
    static let signedPayloadRecordsLocalIntegrityOnly = true
}

enum C50IncumbentContentProvenanceBoundaryV1 {
    static let fileDigestAndProfileReleaseAreRequired = true
    static let providerAvailabilityIsNotCanonicalProvenance = true
    static let acceptedContentKeepsExistingProvenanceOwner = true
}

enum OriginalContentOriginV1: String, CaseIterable, Codable, Hashable, Sendable {
    case humanCapture = "HUMAN_CAPTURE"
    case localImport = "LOCAL_IMPORT"
}

enum FieldReferenceCitationProjectionV1 {
    static func citation(for release: FieldReferenceReleaseV1) throws -> FieldReferenceCitationV1 {
        try FieldReferenceCitationV1(release: release)
    }
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

/// Canonical transform metadata for a bounded, regenerable waveform.  This is
/// descriptive provenance only; it does not authorize audio capture or retain
/// a second copy of the source bytes.
struct WaveformDerivativeV1: Codable, Equatable, Sendable {
    let rendererID: String
    let rendererVersion: String
    let sampleCount: Int

    init(rendererID: String, rendererVersion: String, sampleCount: Int) throws {
        guard ContentContractValidationV1.validID(rendererID),
              ContentContractValidationV1.validVersion(rendererVersion),
              (1...1_000_000).contains(sampleCount) else {
            throw ContentContractFailureV1.invalidValue
        }
        self.rendererID = rendererID
        self.rendererVersion = rendererVersion
        self.sampleCount = sampleCount
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
    case waveform(WaveformDerivativeV1)
    case annotation(AnnotationDerivativeV1)
    case sequence(SequenceDerivativeV1)
    case privacy(PrivacyDerivativeV1)

    var kind: String {
        switch self {
        case .sanitized: return "SANITIZED"
        case .thumbnail: return "THUMBNAIL"
        case .waveform: return "WAVEFORM"
        case .annotation: return "ANNOTATION"
        case .sequence: return "SEQUENCE"
        case .privacy: return "PRIVACY"
        }
    }
}

/// C48 derived review metadata is intentionally a closed, public-surface
/// projection.  It carries the request's public lifecycle facts only; the
/// transferable capability, its proof, the response body, and every raw
/// request/response byte remain outside all derived consumers.
enum C48PortableReviewDerivedFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case requestPublicID = "request_public_id"
    case requestState = "request_state"
    case responseDisposition = "response_disposition"
    case responseAcquisition = "response_acquisition"
    case responseOrigin = "response_origin"
    case responseItemCount = "response_item_count"
    case conflictCount = "conflict_count"
    case historyOnly = "history_only"
}

struct C48PortableReviewDerivedHistoryProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumTokenBytes = 160
    static let maximumItemCount = 128

    let schemaVersion: Int
    let requestPublicID: String
    let requestState: String
    let responseDisposition: String?
    let responseAcquisition: String?
    let responseOrigin: String?
    let responseItemCount: Int
    let conflictCount: Int
    let historyOnly: Bool

    init(
        requestPublicID: String,
        requestState: String,
        responseDisposition: String? = nil,
        responseAcquisition: String? = nil,
        responseOrigin: String? = nil,
        responseItemCount: Int = 0,
        conflictCount: Int = 0,
        historyOnly: Bool = false
    ) throws {
        schemaVersion = Self.schemaVersion
        self.requestPublicID = requestPublicID
        self.requestState = requestState
        self.responseDisposition = responseDisposition
        self.responseAcquisition = responseAcquisition
        self.responseOrigin = responseOrigin
        self.responseItemCount = responseItemCount
        self.conflictCount = conflictCount
        self.historyOnly = historyOnly
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              Self.validToken(requestPublicID),
              Self.validToken(requestState),
              responseDisposition.map(Self.validToken) ?? true,
              responseAcquisition.map(Self.validToken) ?? true,
              responseOrigin.map(Self.validToken) ?? true,
              (0...Self.maximumItemCount).contains(responseItemCount),
              (0...Self.maximumItemCount).contains(conflictCount) else {
            throw ContentContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, requestPublicID, requestState, responseDisposition
        case responseAcquisition, responseOrigin, responseItemCount
        case conflictCount, historyOnly
    }

    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(
            decoder,
            keys: CodingKeys.allCases.map(\.rawValue)
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw ContentContractFailureV1.incompatibleVersion
        }
        try self.init(
            requestPublicID: values.decode(String.self, forKey: .requestPublicID),
            requestState: values.decode(String.self, forKey: .requestState),
            responseDisposition: values.decodeIfPresent(String.self, forKey: .responseDisposition),
            responseAcquisition: values.decodeIfPresent(String.self, forKey: .responseAcquisition),
            responseOrigin: values.decodeIfPresent(String.self, forKey: .responseOrigin),
            responseItemCount: values.decode(Int.self, forKey: .responseItemCount),
            conflictCount: values.decode(Int.self, forKey: .conflictCount),
            historyOnly: values.decode(Bool.self, forKey: .historyOnly)
        )
    }

    static let metadataOnly = true
    static let publicRequestIdentityOnly = true
    static let capabilityBytesExcluded = true
    static let capabilityProofExcluded = true
    static let responseBodyExcluded = true
    static let rawRequestResponseBytesExcluded = true
    static let workspaceAndReplicaIdentityExcluded = true

    static let allowedFieldIDs = C48PortableReviewDerivedFieldV1.allCases
        .map(\.rawValue)
        .sorted()

    static func validateFieldIDs(_ values: [String]) throws {
        guard values == values.sorted(),
              Set(values).count == values.count,
              values.allSatisfy({ allowedFieldIDs.contains($0) }) else {
            throw ContentContractFailureV1.invalidValue
        }
    }

    private static func validToken(_ value: String) -> Bool {
        ContentContractValidationV1.validID(value)
            && value.utf8.count <= maximumTokenBytes
    }
}

extension C48PortableReviewDerivedHistoryProjectionV1 {
    /// Builds the closed projection from the released review state and, when
    /// present, the canonical response record.  The response is decoded only
    /// to select bounded public disposition metadata; capability, proof,
    /// author text, workspace identity, and canonical bytes are never copied
    /// into the projection.
    init(
        state: ReviewRequestStateProjectionV1,
        response: ExternalReviewResponseRecordV1? = nil,
        conflictCount: Int = 0
    ) throws {
        try state.requestPublicID.validate()

        var responseDisposition: String?
        var responseAcquisition: String?
        var responseOrigin: String?
        var responseItemCount = 0

        if let response {
            try response.validate()
            guard response.requestManifest.requestPublicID == state.requestPublicID else {
                throw ContentContractFailureV1.invalidValue
            }
            let payload = try PortableReviewCanonicalCodecV1.decodeCanonicalResponseRecord(
                response.canonicalResponse.canonicalBytes
            )
            let body: ReviewResponseBodyV1
            switch payload {
            case let .portable(envelope):
                body = envelope.body
            case let .originRecorded(origin):
                body = origin.responseBody
            }
            responseDisposition = body.disposition.rawValue
            responseItemCount = body.changeItems.count
            responseOrigin = body.author.source.rawValue
            switch response.source {
            case .portableFile:
                responseAcquisition = ReviewResponseAcquisitionKindV1.portableFile.rawValue
            case .originRecordedElsewhere:
                responseAcquisition = ReviewResponseAcquisitionKindV1.originRecordedElsewhere.rawValue
            }
        }

        let historyOnly: Bool
        switch state.lifecycleState {
        case .historyOnlyTerminal, .historyOnlySuperseded, .historyOnlyClonedOrForked,
             .erasePending, .erased, .unavailableCorruptOrMissing:
            historyOnly = true
        case .issuedNotExported, .exportedAccepting, .responsePendingDecision:
            historyOnly = state.state == .superseded || state.state == .closedWithoutResponse
        }

        try self.init(
            requestPublicID: state.requestPublicID.rawValue,
            requestState: state.state.rawValue,
            responseDisposition: responseDisposition,
            responseAcquisition: responseAcquisition,
            responseOrigin: responseOrigin,
            responseItemCount: responseItemCount,
            conflictCount: conflictCount,
            historyOnly: historyOnly
        )
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
    private enum CodingKeys: String, CodingKey, CaseIterable { case kind, sanitized, thumbnail, waveform, annotation, sequence, privacy }
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
        case "WAVEFORM":
            try ContentClosedCodingV1.requireExact(decoder, keys: ["kind", "waveform"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self = .waveform(try c.decode(WaveformDerivativeV1.self, forKey: .waveform))
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
        case .waveform(let value): try c.encode(value, forKey: .waveform)
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

extension WaveformDerivativeV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case rendererID, rendererVersion, sampleCount }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(rendererID: c.decode(String.self, forKey: .rendererID), rendererVersion: c.decode(String.self, forKey: .rendererVersion), sampleCount: c.decode(Int.self, forKey: .sampleCount))
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rendererID, forKey: .rendererID)
        try c.encode(rendererVersion, forKey: .rendererVersion)
        try c.encode(sampleCount, forKey: .sampleCount)
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

// MARK: - C24 accessible-document provenance boundary

/// Alternate text provenance and decorative state are facts recorded on the
/// canonical accessible-document node.  This adapter only revalidates those
/// facts; it never synthesizes text from private evidence or an assessor.
enum AccessibleDocumentProvenanceBoundaryV1 {
    static let alternateTextMustHaveRecordedProvenance = true
    static let decorativeFiguresHaveNoAlternateText = true
    static let nonFiguresHaveNoAlternateText = true
    static let excludesAssessorIdentity = true
    static let excludesHiddenEvidence = true

    static func validateNode(_ node: AccessibleDocumentNodeV1) throws {
        try node.validate()
        if node.role == .figure, !node.decorative {
            guard (node.alternateText == nil)
                == (node.alternateTextProvenance == .notProvided) else {
                throw AccessibleDocumentFailureV1.inventedAlternateText
            }
        }
    }

    static func validateTree(_ tree: AccessibleDocumentSemanticTreeV1) throws {
        try AccessibleDocumentContentReferenceBoundaryV1.validateAudienceSafeTree(tree)
        try tree.nodes.forEach(validateNode)
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

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Content_ContentProvenanceContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Content_ContentProvenanceContractsV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Domain_Content_ContentProvenanceContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Content/ContentProvenanceContractsV1.swift", role: .content)
}

enum C31LightingContentProvenanceBoundaryV1 {
    static let observationsRemainUserObservedOrMeasured = true
    static let derivativeProvenanceRemainsSeparate = true
    static let noClaimIsInferredFromPhotoOrTimestamp = true

    static func accepts(_ provenance: ContentOriginalProvenanceV1) -> Bool {
        !provenance.workspaceID.isEmpty && !provenance.contentID.isEmpty
    }
}
// MARK: - C32 assistance content provenance boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Content_ContentProvenanceContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalSourceDigestIsReviewProvenanceOnly = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

// MARK: - C33 temporal evidence derivative provenance

enum TemporalEvidenceProvenanceBoundaryV1 {
    static let originalCanBeOverwrittenByDerivative = false
    static let derivativesAreRegenerable = true
    static let maximumDerivativeByteCount: Int64 = 64 * 1_024 * 1_024

    static func validate(
        clip: TemporalEvidenceClipV1,
        derivative: TemporalEvidenceDerivativeV1
    ) throws {
        try clip.validateIntrinsic()
        try derivative.validate(clip: clip)
        let provenance = derivative.provenance
        let expectedTransform: Bool
        switch (derivative.kind, provenance.transform) {
        case (.thumbnail, .thumbnail): expectedTransform = true
        case (.waveform, .waveform): expectedTransform = true
        default: expectedTransform = false
        }
        let compatibleMedia: Bool
        switch derivative.kind {
        case .thumbnail:
            compatibleMedia = clip.facts.kind == .video
                && derivative.content.mediaType.hasPrefix("image/")
        case .waveform:
            compatibleMedia = clip.facts.kind == .audio
                && (derivative.content.mediaType.hasPrefix("image/")
                    || derivative.content.mediaType == "application/json")
        }
        guard derivative.source.contentID == clip.original.contentID,
              clip.original.digests.digest(for: derivative.source.digest.algorithm)
                == derivative.source.digest,
              derivative.content.byteRole == .derivative,
              derivative.content.contentID != clip.original.contentID,
              derivative.content.byteLength >= 0,
              derivative.content.byteLength <= maximumDerivativeByteCount,
              provenance.workspaceID == clip.original.workspaceID,
              provenance.sources == [derivative.source],
              provenance.derivativeContentID == derivative.content.contentID,
              provenance.derivativeDigest
                == derivative.content.digests.digest(for: provenance.derivativeDigest.algorithm),
              expectedTransform, compatibleMedia else {
            throw ContentContractFailureV1.orphanEvidence
        }
        try ContentProvenanceGraphV1.validate(
            references: [clip.original, derivative.content],
            originals: [clip.originalProvenance],
            derivatives: [provenance]
        )
    }
}

/// C45 label output provenance binds the frozen plan, renderer, and template releases.
enum C45AssetLabelBoundary_ContentProvenanceContractsV1 {
    static func validate(_ plan: AssetLabelGenerationPlanV1) throws { try plan.validate() }
    static let claimsPhysicalScanAcceptance = false
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_Content_ContentProvenanceContractsV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}

enum C48PortableReviewContentProjectionBoundaryV1 {
    static let derivedMetadataType = C48PortableReviewDerivedHistoryProjectionV1.self
    static let metadataOnly = C48PortableReviewDerivedHistoryProjectionV1.metadataOnly
    static let capabilityBytesExcluded = C48PortableReviewDerivedHistoryProjectionV1.capabilityBytesExcluded
    static let capabilityProofExcluded = C48PortableReviewDerivedHistoryProjectionV1.capabilityProofExcluded
    static let responseBodyExcluded = C48PortableReviewDerivedHistoryProjectionV1.responseBodyExcluded
    static let rawRequestResponseBytesExcluded = C48PortableReviewDerivedHistoryProjectionV1.rawRequestResponseBytesExcluded
    static let workspaceAndReplicaIdentityExcluded = C48PortableReviewDerivedHistoryProjectionV1.workspaceAndReplicaIdentityExcluded

    static func validate(_ projection: C48PortableReviewDerivedHistoryProjectionV1) throws {
        try projection.validate()
    }
}

// MARK: - C49 work-resource provenance projection

enum C49WorkResourceContentProvenanceBoundaryV1 {
    static let provenanceIsTheProjectionDigest = true
    static let rawSourceBytesAreProjected = false
    static let liveInventoryProvenanceIsProjected = false

    static func digest(_ projection: C49WorkResourceReportProjectionV1) throws -> String {
        try C49WorkResourceProjectionSupportV1.validate(projection)
        return projection.projectionSHA256
    }
}

enum C34RouteAdoptionBoundary_ContentProvenanceContractsV1 {
    static let canonicalRegistryType = RouteRegistryV1.self
    static let resolutionResultType = RouteResolutionResultV1.self
    static let routeStoresProvenanceBytes = false
}
enum C52ServiceRequestBoundary_ContentProvenanceContractsV1 {
    static let sourceKind: ServiceRequestSourceKindV1 = .portableSubmission
    static let requesterAssertionType: ServiceRequestRequesterAssertionV1.Type = ServiceRequestRequesterAssertionV1.self
    static let contactAssertionType: ServiceRequestContactAssertionV1.Type = ServiceRequestContactAssertionV1.self
    static let requesterIdentityIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.requesterIdentityIsVerified
    static let contactAssertionWording: String = "SELF_ASSERTED_UNVERIFIED"
    static let urgencyIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.urgencyIsVerified
    static let cleartextIsReadableAndForwardable: Bool = PortableServiceRequestFormatBoundaryV1.submissionIsCleartext && PortableServiceRequestFormatBoundaryV1.invitationIsReadableAndForwardable
    static let providerContactPurposeSeparationRequired: Bool = true
    static let canonicalSourceBytesAreAuthoritative: Bool = true
    static let duplicateCandidatesAreDerived: Bool = !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityMayBecomeWorkspaceTruth: Bool = ServiceRequestNoncanonicalBoundaryV1.rawCapabilityIsWorkspaceTruth
    static let automaticWorkOrDuplicateActionPermitted: Bool = ServiceRequestNoncanonicalBoundaryV1.automaticWorkCreationPermitted || ServiceRequestNoncanonicalBoundaryV1.automaticDuplicateMergePermitted
    static let excludedSurfaces: [String] = ["REPORT", "SEARCH", "DIAGNOSTIC", "LIFECYCLE", "COMPATIBILITY", "BACKUP", "DELETE"]
}

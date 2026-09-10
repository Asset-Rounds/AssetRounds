import Foundation

enum V30CatalogReleaseContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case identityMismatch
    case incompatibleReader
    case invalidSuccessor
    case payloadMismatch
    case nonCanonicalPayload
    case unsupportedQualification
}

/// A release ID binds its monotonic revision to the complete descriptor payload.
/// It is deliberately separate from the legacy catalog digest, whose bytes remain
/// governed by `LocalizationCatalogReleaseV1`.
struct V30CatalogReleaseIDV1: Codable, Equatable, Hashable, Sendable {
    let digest: String
    let revision: Int

    init(digest: String, revision: Int) throws {
        guard KernelCanonicalHashV1.validSHA256(digest), revision > 0 else {
            throw V30CatalogReleaseContractFailureV1.invalidValue
        }
        self.digest = digest
        self.revision = revision
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            digest: container.decode(String.self, forKey: .digest),
            revision: container.decode(Int.self, forKey: .revision)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(digest, forKey: .digest)
        try container.encode(revision, forKey: .revision)
    }

    private enum CodingKeys: String, CodingKey { case digest, revision }
}

enum V30CatalogReleaseQualificationV1: String, Codable, Sendable {
    /// Validation of the inherited English/Base catalog only; never final release credit.
    case inheritedEnglish = "INHERITED_ENGLISH"
    /// Test-fixture data only; never a distributable catalog release.
    case provisionalFixture = "PROVISIONAL_FIXTURE"
}

/// The versioned V30 envelope around the unchanged legacy catalog digest model.
/// C08 deliberately permits only inherited-English or fixture validation. Candidate,
/// translator, and reviewer fields are present as a future provenance schema but
/// cannot be populated under either C08 qualification.
struct V30CatalogReleaseDescriptorV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let releaseID: V30CatalogReleaseIDV1
    let family: String
    let revision: Int
    let language: AppLanguageTagV1
    let minimumReaderSchemaVersion: Int
    let maximumReaderSchemaVersion: Int
    let sourceSchemaVersion: Int
    let sourceRevision: String
    let termbaseRevision: String
    let qualification: V30CatalogReleaseQualificationV1
    let legacyRelease: LocalizationCatalogReleaseV1
    let supersedesReleaseID: V30CatalogReleaseIDV1?

    // Schema-only provenance fields. C08 validation requires them to be nil.
    let candidateHead: String?
    let candidateTree: String?
    let translationRevision: String?
    let translatorReference: String?
    let reviewerReference: String?
    let reviewBindingSchemaVersion: Int?

    init(
        schemaVersion: Int = Self.schemaVersion,
        family: String,
        revision: Int,
        language: AppLanguageTagV1,
        minimumReaderSchemaVersion: Int,
        maximumReaderSchemaVersion: Int,
        sourceSchemaVersion: Int,
        sourceRevision: String,
        termbaseRevision: String,
        qualification: V30CatalogReleaseQualificationV1,
        legacyRelease: LocalizationCatalogReleaseV1,
        supersedesReleaseID: V30CatalogReleaseIDV1? = nil,
        candidateHead: String? = nil,
        candidateTree: String? = nil,
        translationRevision: String? = nil,
        translatorReference: String? = nil,
        reviewerReference: String? = nil,
        reviewBindingSchemaVersion: Int? = nil
    ) throws {
        self.schemaVersion = schemaVersion
        self.family = family
        self.revision = revision
        self.language = language
        self.minimumReaderSchemaVersion = minimumReaderSchemaVersion
        self.maximumReaderSchemaVersion = maximumReaderSchemaVersion
        self.sourceSchemaVersion = sourceSchemaVersion
        self.sourceRevision = sourceRevision
        self.termbaseRevision = termbaseRevision
        self.qualification = qualification
        self.legacyRelease = legacyRelease
        self.supersedesReleaseID = supersedesReleaseID
        self.candidateHead = candidateHead
        self.candidateTree = candidateTree
        self.translationRevision = translationRevision
        self.translatorReference = translatorReference
        self.reviewerReference = reviewerReference
        self.reviewBindingSchemaVersion = reviewBindingSchemaVersion
        self.releaseID = try Self.makeReleaseID(
            schemaVersion: schemaVersion,
            family: family,
            revision: revision,
            language: language,
            minimumReaderSchemaVersion: minimumReaderSchemaVersion,
            maximumReaderSchemaVersion: maximumReaderSchemaVersion,
            sourceSchemaVersion: sourceSchemaVersion,
            sourceRevision: sourceRevision,
            termbaseRevision: termbaseRevision,
            qualification: qualification,
            legacyRelease: legacyRelease,
            supersedesReleaseID: supersedesReleaseID,
            candidateHead: candidateHead,
            candidateTree: candidateTree,
            translationRevision: translationRevision,
            translatorReference: translatorReference,
            reviewerReference: reviewerReference,
            reviewBindingSchemaVersion: reviewBindingSchemaVersion
        )
        try validate()
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let suppliedReleaseID = try container.decode(V30CatalogReleaseIDV1.self, forKey: .releaseID)
        let value = try Self(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            family: container.decode(String.self, forKey: .family),
            revision: container.decode(Int.self, forKey: .revision),
            language: container.decode(AppLanguageTagV1.self, forKey: .language),
            minimumReaderSchemaVersion: container.decode(
                Int.self, forKey: .minimumReaderSchemaVersion
            ),
            maximumReaderSchemaVersion: container.decode(
                Int.self, forKey: .maximumReaderSchemaVersion
            ),
            sourceSchemaVersion: container.decode(Int.self, forKey: .sourceSchemaVersion),
            sourceRevision: container.decode(String.self, forKey: .sourceRevision),
            termbaseRevision: container.decode(String.self, forKey: .termbaseRevision),
            qualification: container.decode(
                V30CatalogReleaseQualificationV1.self, forKey: .qualification
            ),
            legacyRelease: container.decode(LocalizationCatalogReleaseV1.self, forKey: .legacyRelease),
            supersedesReleaseID: container.decodeIfPresent(
                V30CatalogReleaseIDV1.self, forKey: .supersedesReleaseID
            ),
            candidateHead: container.decodeIfPresent(String.self, forKey: .candidateHead),
            candidateTree: container.decodeIfPresent(String.self, forKey: .candidateTree),
            translationRevision: container.decodeIfPresent(String.self, forKey: .translationRevision),
            translatorReference: container.decodeIfPresent(String.self, forKey: .translatorReference),
            reviewerReference: container.decodeIfPresent(String.self, forKey: .reviewerReference),
            reviewBindingSchemaVersion: container.decodeIfPresent(
                Int.self, forKey: .reviewBindingSchemaVersion
            )
        )
        guard suppliedReleaseID == value.releaseID else {
            throw V30CatalogReleaseContractFailureV1.identityMismatch
        }
        self = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(releaseID, forKey: .releaseID)
        try container.encode(family, forKey: .family)
        try container.encode(revision, forKey: .revision)
        try container.encode(language, forKey: .language)
        try container.encode(minimumReaderSchemaVersion, forKey: .minimumReaderSchemaVersion)
        try container.encode(maximumReaderSchemaVersion, forKey: .maximumReaderSchemaVersion)
        try container.encode(sourceSchemaVersion, forKey: .sourceSchemaVersion)
        try container.encode(sourceRevision, forKey: .sourceRevision)
        try container.encode(termbaseRevision, forKey: .termbaseRevision)
        try container.encode(qualification, forKey: .qualification)
        try container.encode(legacyRelease, forKey: .legacyRelease)
        try container.encodeIfPresent(supersedesReleaseID, forKey: .supersedesReleaseID)
        try container.encodeIfPresent(candidateHead, forKey: .candidateHead)
        try container.encodeIfPresent(candidateTree, forKey: .candidateTree)
        try container.encodeIfPresent(translationRevision, forKey: .translationRevision)
        try container.encodeIfPresent(translatorReference, forKey: .translatorReference)
        try container.encodeIfPresent(reviewerReference, forKey: .reviewerReference)
        try container.encodeIfPresent(reviewBindingSchemaVersion, forKey: .reviewBindingSchemaVersion)
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              Self.validFamily(family), revision > 0,
              minimumReaderSchemaVersion > 0,
              minimumReaderSchemaVersion <= maximumReaderSchemaVersion,
              sourceSchemaVersion > 0,
              Self.validRevisionReference(sourceRevision),
              Self.validRevisionReference(termbaseRevision),
              releaseID.revision == revision else {
            throw V30CatalogReleaseContractFailureV1.invalidValue
        }
        try legacyRelease.validateIdentity()
        if revision == 1 {
            guard supersedesReleaseID == nil else {
                throw V30CatalogReleaseContractFailureV1.invalidSuccessor
            }
        } else {
            guard let supersedesReleaseID,
                  supersedesReleaseID != releaseID,
                  supersedesReleaseID.revision < revision else {
                throw V30CatalogReleaseContractFailureV1.invalidSuccessor
            }
        }
        guard language == .english,
              candidateHead == nil, candidateTree == nil,
              translationRevision == nil, translatorReference == nil,
              reviewerReference == nil, reviewBindingSchemaVersion == nil else {
            throw V30CatalogReleaseContractFailureV1.unsupportedQualification
        }
        let expectedID = try Self.makeReleaseID(
            schemaVersion: schemaVersion,
            family: family,
            revision: revision,
            language: language,
            minimumReaderSchemaVersion: minimumReaderSchemaVersion,
            maximumReaderSchemaVersion: maximumReaderSchemaVersion,
            sourceSchemaVersion: sourceSchemaVersion,
            sourceRevision: sourceRevision,
            termbaseRevision: termbaseRevision,
            qualification: qualification,
            legacyRelease: legacyRelease,
            supersedesReleaseID: supersedesReleaseID,
            candidateHead: candidateHead,
            candidateTree: candidateTree,
            translationRevision: translationRevision,
            translatorReference: translatorReference,
            reviewerReference: reviewerReference,
            reviewBindingSchemaVersion: reviewBindingSchemaVersion
        )
        guard releaseID == expectedID else {
            throw V30CatalogReleaseContractFailureV1.identityMismatch
        }
    }

    func validateCompatible(readerVersion: Int) throws {
        try validate()
        guard (minimumReaderSchemaVersion...maximumReaderSchemaVersion).contains(readerVersion) else {
            throw V30CatalogReleaseContractFailureV1.incompatibleReader
        }
    }

    func validatePayloads(
        sourceCatalog: Data,
        registry: Data,
        localeManifest: Data
    ) throws {
        try validate()
        try legacyRelease.validate(
            sourceCatalog: sourceCatalog, registry: registry, localeManifest: localeManifest
        )
        guard sourceSchemaVersion == 1,
              let sourceObject = try JSONSerialization.jsonObject(with: sourceCatalog) as? [String: Any],
              sourceObject["version"] as? String == "1.0" else {
            throw V30CatalogReleaseContractFailureV1.payloadMismatch
        }
        let decodedRegistry = try JSONDecoder().decode(LocalizationKeyRegistryV1.self, from: registry)
        let decodedManifest = try JSONDecoder().decode(LocalizationLocaleManifestV1.self, from: localeManifest)
        try decodedRegistry.validate()
        try decodedManifest.validate()
        guard try LocalizationContractCanonicalCodecV1.encode(decodedRegistry) == registry,
              try LocalizationContractCanonicalCodecV1.encode(decodedManifest) == localeManifest else {
            throw V30CatalogReleaseContractFailureV1.nonCanonicalPayload
        }
    }

    func validateSuccessor(of previous: Self) throws {
        try validate()
        try previous.validate()
        guard family == previous.family,
              language == previous.language,
              revision > previous.revision,
              supersedesReleaseID == previous.releaseID,
              sourceSchemaVersion >= previous.sourceSchemaVersion,
              minimumReaderSchemaVersion <= previous.minimumReaderSchemaVersion,
              maximumReaderSchemaVersion >= previous.maximumReaderSchemaVersion else {
            throw V30CatalogReleaseContractFailureV1.invalidSuccessor
        }
    }

    func validateSuccessor(
        of previous: Self,
        keyRegistry: LocalizationKeyRegistryV1,
        previousKeyRegistry: LocalizationKeyRegistryV1
    ) throws {
        try validateSuccessor(of: previous)
        try keyRegistry.validateSuccessor(of: previousKeyRegistry)
    }

    private struct IdentityPayload: Codable {
        let schemaVersion: Int
        let family: String
        let revision: Int
        let language: AppLanguageTagV1
        let minimumReaderSchemaVersion: Int
        let maximumReaderSchemaVersion: Int
        let sourceSchemaVersion: Int
        let sourceRevision: String
        let termbaseRevision: String
        let qualification: V30CatalogReleaseQualificationV1
        let legacyRelease: LocalizationCatalogReleaseV1
        let supersedesReleaseID: V30CatalogReleaseIDV1?
        let candidateHead: String?
        let candidateTree: String?
        let translationRevision: String?
        let translatorReference: String?
        let reviewerReference: String?
        let reviewBindingSchemaVersion: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, releaseID, family, revision, language
        case minimumReaderSchemaVersion, maximumReaderSchemaVersion, sourceSchemaVersion
        case sourceRevision, termbaseRevision, qualification, legacyRelease, supersedesReleaseID
        case candidateHead, candidateTree, translationRevision, translatorReference
        case reviewerReference, reviewBindingSchemaVersion
    }

    private static func makeReleaseID(
        schemaVersion: Int,
        family: String,
        revision: Int,
        language: AppLanguageTagV1,
        minimumReaderSchemaVersion: Int,
        maximumReaderSchemaVersion: Int,
        sourceSchemaVersion: Int,
        sourceRevision: String,
        termbaseRevision: String,
        qualification: V30CatalogReleaseQualificationV1,
        legacyRelease: LocalizationCatalogReleaseV1,
        supersedesReleaseID: V30CatalogReleaseIDV1?,
        candidateHead: String?,
        candidateTree: String?,
        translationRevision: String?,
        translatorReference: String?,
        reviewerReference: String?,
        reviewBindingSchemaVersion: Int?
    ) throws -> V30CatalogReleaseIDV1 {
        let bytes = try LocalizationContractCanonicalCodecV1.encode(IdentityPayload(
            schemaVersion: schemaVersion,
            family: family,
            revision: revision,
            language: language,
            minimumReaderSchemaVersion: minimumReaderSchemaVersion,
            maximumReaderSchemaVersion: maximumReaderSchemaVersion,
            sourceSchemaVersion: sourceSchemaVersion,
            sourceRevision: sourceRevision,
            termbaseRevision: termbaseRevision,
            qualification: qualification,
            legacyRelease: legacyRelease,
            supersedesReleaseID: supersedesReleaseID,
            candidateHead: candidateHead,
            candidateTree: candidateTree,
            translationRevision: translationRevision,
            translatorReference: translatorReference,
            reviewerReference: reviewerReference,
            reviewBindingSchemaVersion: reviewBindingSchemaVersion
        ))
        return try V30CatalogReleaseIDV1(
            digest: KernelCanonicalHashV1.sha256(bytes), revision: revision
        )
    }

    private static func validFamily(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.utf8.allSatisfy {
                (0x61...0x7A).contains($0) || (0x30...0x39).contains($0)
                    || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
            }
    }

    private static func validRevisionReference(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

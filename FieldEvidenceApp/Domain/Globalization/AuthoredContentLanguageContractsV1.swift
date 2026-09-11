import Foundation

enum AuthoredContentLanguageFailureV1: Error, Equatable, Sendable {
    case invalidSource, invalidLanguage, invalidOwnerVersion, invalidLicensedAuthority
    case invalidTranslation, sourceBytesMismatch, unsupportedLayer
}

/// Content ownership is independent of the language selected for app UI.
enum AuthoredContentLayerV1: String, Codable, CaseIterable, Sendable {
    case appUI = "APP_UI"
    case adminTemplate = "ADMIN_TEMPLATE"
    case instruction = "INSTRUCTION"
    case inspectorCustomerEvidence = "INSPECTOR_CUSTOMER_EVIDENCE"
    case derivedTranslation = "DERIVED_TRANSLATION"
    case reportChrome = "REPORT_CHROME"
    case licensedJurisdictionContent = "LICENSED_JURISDICTION_CONTENT"

    var usesAppCatalog: Bool { self == .appUI || self == .reportChrome }
    var preservesAuthoredSource: Bool { !usesAppCatalog }
}

/// A declaration about an exact owner-issued release, not permission to create
/// a translation. The incumbent release resolver must verify this binding.
struct AuthoredContentOwnerVersionV1: Codable, Equatable, Sendable {
    let ownerID: String
    let version: String
    let releaseSHA256: String

    init(ownerID: String, version: String, releaseSHA256: String) throws {
        self.ownerID = ownerID; self.version = version; self.releaseSHA256 = releaseSHA256
        try validate()
    }

    func validate() throws {
        guard AuthoredContentLanguageValidationV1.token(ownerID),
              AuthoredContentLanguageValidationV1.token(version),
              KernelCanonicalHashV1.validSHA256(releaseSHA256) else {
            throw AuthoredContentLanguageFailureV1.invalidOwnerVersion
        }
    }
}

/// All five declarations are required. These identifiers are provenance,
/// not a finding that a license, reviewer, or legal scope has been qualified.
struct LicensedContentLanguageAuthorityV1: Codable, Equatable, Sendable {
    let licenseID: String
    let sourceID: String
    let jurisdiction: ProjectJurisdictionV1
    let reviewerID: String
    let version: String

    init(licenseID: String, sourceID: String, jurisdiction: ProjectJurisdictionV1,
         reviewerID: String, version: String) throws {
        self.licenseID = licenseID; self.sourceID = sourceID; self.jurisdiction = jurisdiction
        self.reviewerID = reviewerID; self.version = version
        try validate()
    }

    func validate() throws {
        guard [licenseID, sourceID, reviewerID, version].allSatisfy(AuthoredContentLanguageValidationV1.token) else {
            throw AuthoredContentLanguageFailureV1.invalidLicensedAuthority
        }
        _ = try ProjectJurisdictionV1(countryCode: jurisdiction.countryCode,
                                     subdivisionCode: jurisdiction.subdivisionCode)
    }
}

/// Disposable language metadata. It is deliberately outside canonical source
/// encoders, journals, backups and report snapshot identity. No source text is
/// copied into this value and no language is inferred from current preferences.
struct AuthoredContentLanguageSourceV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let sourceID: String
    let revision: UInt64
    let sourceSHA256: String
    let layer: AuthoredContentLayerV1
    let language: AuthoredContentLanguageV1
    let ownerVersion: AuthoredContentOwnerVersionV1?
    let licensedAuthority: LicensedContentLanguageAuthorityV1?
    /// Exact current privacy/redaction manifest digest, when present. Removing
    /// or changing it invalidates a candidate even if original bytes survive.
    let redactionSHA256: String?

    init(workspaceID: WorkspaceID, sourceID: String, revision: UInt64,
         sourceSHA256: String, layer: AuthoredContentLayerV1,
         language: AuthoredContentLanguageV1,
         ownerVersion: AuthoredContentOwnerVersionV1? = nil,
         licensedAuthority: LicensedContentLanguageAuthorityV1? = nil,
         redactionSHA256: String? = nil) throws {
        self.workspaceID = workspaceID; self.sourceID = sourceID; self.revision = revision
        self.sourceSHA256 = sourceSHA256; self.layer = layer; self.language = language
        self.ownerVersion = ownerVersion; self.licensedAuthority = licensedAuthority
        self.redactionSHA256 = redactionSHA256
        try validate()
    }

    func validate() throws {
        guard workspaceID.rawValue != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)),
              AuthoredContentLanguageValidationV1.token(sourceID), revision > 0,
              KernelCanonicalHashV1.validSHA256(sourceSHA256),
              redactionSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true,
              layer != .derivedTranslation else {
            throw AuthoredContentLanguageFailureV1.invalidSource
        }
        try AuthoredContentLanguageValidationV1.language(language)
        try ownerVersion?.validate(); try licensedAuthority?.validate()
        switch layer {
        case .adminTemplate, .instruction:
            guard ownerVersion != nil, licensedAuthority == nil else {
                throw AuthoredContentLanguageFailureV1.invalidOwnerVersion
            }
        case .licensedJurisdictionContent:
            guard ownerVersion != nil, licensedAuthority != nil else {
                throw AuthoredContentLanguageFailureV1.invalidLicensedAuthority
            }
        case .appUI, .reportChrome, .inspectorCustomerEvidence:
            guard ownerVersion == nil, licensedAuthority == nil else {
                throw AuthoredContentLanguageFailureV1.invalidSource
            }
        case .derivedTranslation: throw AuthoredContentLanguageFailureV1.invalidSource
        }
    }

    func validate(sourceBytes: Data) throws {
        try validate()
        guard sourceSHA256 == AuthoredContentLanguageValidationV1.sha256(sourceBytes) else {
            throw AuthoredContentLanguageFailureV1.sourceBytesMismatch
        }
    }
}

/// Metadata for assessing an externally described derivative. Construction is
/// not service authorization, professional review, or permission to display it.
/// The app does not create, retain, send, or return translated customer text.
struct DerivedContentTranslationProvenanceV1: Codable, Equatable, Sendable {
    let artifactID: String
    let artifactSHA256: String
    let source: AuthoredContentLanguageSourceV1
    let targetLanguage: AuthoredContentLanguageV1
    let producerID: String
    let producerVersion: String

    init(artifactID: String, artifactSHA256: String, source: AuthoredContentLanguageSourceV1,
         targetLanguage: AuthoredContentLanguageV1, producerID: String, producerVersion: String) throws {
        self.artifactID = artifactID; self.artifactSHA256 = artifactSHA256; self.source = source
        self.targetLanguage = targetLanguage; self.producerID = producerID; self.producerVersion = producerVersion
        try validate()
    }

    func validate() throws {
        try source.validate(); try AuthoredContentLanguageValidationV1.language(targetLanguage)
        guard [artifactID, producerID, producerVersion].allSatisfy(AuthoredContentLanguageValidationV1.token),
              artifactID != source.sourceID, KernelCanonicalHashV1.validSHA256(artifactSHA256),
              targetLanguage != .unknown, targetLanguage != source.language,
              [.adminTemplate, .instruction, .inspectorCustomerEvidence].contains(source.layer) else {
            throw AuthoredContentLanguageFailureV1.invalidTranslation
        }
    }
}

enum DerivedContentTranslationStateV1: String, Codable, Sendable {
    /// Matches the supplied source. The source resolver, not this assessment,
    /// establishes whether those inputs describe current canonical state.
    case sourceBindingCurrent = "SOURCE_BINDING_CURRENT"
    case sourceUnavailable = "SOURCE_UNAVAILABLE"
    case sourceEdited = "SOURCE_EDITED"
    case sourceRedacted = "SOURCE_REDACTED"
    case writerInvalidated = "WRITER_INVALIDATED"
    case sessionExpired = "SESSION_EXPIRED"
}

struct DerivedContentTranslationAssessmentV1: Equatable, Sendable {
    let state: DerivedContentTranslationStateV1
    /// A source binding match never enables the future translation service.
    var mayDisplayTranslation: Bool { false }
    var preservesSource: Bool { true }
    var layer: AuthoredContentLayerV1 { .derivedTranslation }
}

enum AuthoredContentLanguageValidationV1 {
    static func token(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || [45, 46, 58, 95].contains($0)
        }
    }

    static func language(_ value: AuthoredContentLanguageV1) throws {
        if case let .known(tag) = value {
            guard AppLanguageTagV1.isWellFormedBCP47(tag) else {
                throw AuthoredContentLanguageFailureV1.invalidLanguage
            }
        }
    }

    /// Hash exact bytes; do not trim, normalize Unicode, case-fold or translate.
    static func sha256(_ bytes: Data) -> String {
        KernelCanonicalHashV1.sha256(bytes)
    }
}

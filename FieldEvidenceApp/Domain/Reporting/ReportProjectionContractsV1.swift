import Foundation

enum ReportAudienceV1: String, Codable, CaseIterable, Hashable, Sendable {
    case internalUse = "INTERNAL"
    case customerSafe = "CUSTOMER_SAFE"
}

enum ReportDetailLevelV1: String, Codable, CaseIterable, Hashable, Sendable {
    case summary = "SUMMARY"
    case complete = "COMPLETE"
}

enum ReportProjectionFormatV1: String, Codable, CaseIterable, Hashable, Sendable {
    case pdf = "PDF"
    case openJSON = "OPEN_JSON"
    case structuredText = "STRUCTURED_TEXT"
    case formulaSafeCSV = "FORMULA_SAFE_CSV"
    case media = "MEDIA"
    case manifest = "MANIFEST"
}

enum ReportMediaLayoutV1: String, Codable, CaseIterable, Hashable, Sendable {
    case none = "NONE"
    case compactGrid = "COMPACT_GRID"
    case standardGrid = "STANDARD_GRID"
    case fullWidth = "FULL_WIDTH"
}

enum ReportOrientationV1: String, Codable, CaseIterable, Hashable, Sendable {
    case portrait = "PORTRAIT"
    case landscape = "LANDSCAPE"
}

enum ReportPackagingV1: String, Codable, CaseIterable, Hashable, Sendable {
    case combined = "COMBINED"
    case separatePerWorkItem = "SEPARATE_PER_WORK_ITEM"
}

enum ReportPrivacyClassV1: String, Codable, CaseIterable, Hashable, Sendable {
    case mandatoryPublicTruth = "MANDATORY_PUBLIC_TRUTH"
    case audienceSafe = "AUDIENCE_SAFE"
    case internalOnly = "INTERNAL_ONLY"
}

/// Additive report policy for the C38 accountability projection.  The
/// section is audience-safe because it carries local assertions and recorded
/// provenance only; contact points, identity verification, and legal-signature
/// claims remain outside this projection.
enum ReportAccountabilityProjectionPolicyV1 {
    static let sectionID = "accountability"
    static let sectionVersion = 1
    static let projectionVersion = "report-accountability-v1"
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let excludesContactPoints = true
    static let excludesIdentityAndLegalClaims = true
    static let supportedFormats: [ReportProjectionFormatV1] = [
        .openJSON, .structuredText,
    ]

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }
}

/// Additive C39 report policy.  Semantic and lifecycle records are frozen
/// projections; operational disposition, safety/recall claims, and raw
/// product-identifier values are never inferred or emitted by this section.
enum ReportAssetSemanticsProjectionPolicyV1 {
    static let sectionID = "asset-semantics"
    static let sectionVersion = 1
    static let projectionVersion = "report-asset-semantics-v1"
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let excludesOperationalDisposition = true
    static let excludesProductIdentifierValues = true
    static let excludesSafetyAndRecallClaims = true
    static let supportedFormats: [ReportProjectionFormatV1] = [
        .openJSON, .structuredText,
    ]

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }
}

/// C40 authority and criterion facts are reported as an exact historic basis,
/// never as an app-origin legal, safety, compliance, AHJ, or professional claim.
enum ReportAuthorityCriterionProjectionPolicyV1 {
    static let sectionID = "authority-criterion"
    static let sectionVersion = 1
    static let projectionVersion = "report-authority-criterion-v1"
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let requiredWording = "assessed against"
    static let localizationKeys: [AuthorityCriterionLocalizationKeyV1] = [
        .authoritySource,
        .applicability,
        .criterionResult,
        .severity,
        .measurementProtocol,
        .technicalBasis,
        .assessedAgainst,
        .nextStep,
    ]
    static let excludesLicensedSourceBytes = true
    static let excludesRawLocators = true
    static let excludesLegalSafetyComplianceClaims = true
    static let supportedFormats: [ReportProjectionFormatV1] = [
        .openJSON, .structuredText,
    ]

    static func applicabilityLocalizationKey(
        _ disposition: ApplicabilityDispositionV1
    ) -> AuthorityCriterionLocalizationKeyV1 {
        AuthorityCriterionLocalizationKeyV1.applicabilityKey(disposition)
    }

    static func resultLocalizationKey(
        _ result: ScreeningCriterionResultV1
    ) -> AuthorityCriterionLocalizationKeyV1 {
        AuthorityCriterionLocalizationKeyV1.resultKey(result)
    }

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }
}

/// C41 frozen functional-relationship report section.  This is a typed,
/// audience-safe history projection: it carries descriptor identity, direction,
/// state, bounds, and site policy without turning an association into a
/// placement, ownership, authorization, compliance, or telemetry claim.
enum ReportFunctionalRelationshipsProjectionPolicyV1 {
    static let sectionID = "functional-relationships"
    static let sectionVersion = 1
    static let projectionVersion = "report-functional-relationships-v1"
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let supportedFormats: [ReportProjectionFormatV1] = [.openJSON, .structuredText]
    static let requiredTypedLabels = true
    static let excludesOwnershipAuthorizationComplianceClaims = true
    static let excludesTelemetryAndOperationalClaims = true
    static let excludesRawLocators = true

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }

    static func directionLocalizationKey(
        _ direction: FunctionalRelationshipDirectionV1
    ) -> FunctionalRelationshipLocalizationKeyV1 {
        FunctionalRelationshipLocalizationKeyV1.directionKey(direction)
    }

    static func symmetryLocalizationKey(
        _ symmetry: FunctionalRelationshipSymmetryV1
    ) -> FunctionalRelationshipLocalizationKeyV1 {
        FunctionalRelationshipLocalizationKeyV1.symmetryKey(symmetry)
    }

    static func eventStateLocalizationKey(
        _ action: AssetFunctionalRelationshipEventActionV1
    ) -> FunctionalRelationshipLocalizationKeyV1 {
        FunctionalRelationshipLocalizationKeyV1.eventStateKey(action)
    }

    static func siteLocalizationKey(
        _ policy: FunctionalRelationshipSitePolicyV1
    ) -> FunctionalRelationshipLocalizationKeyV1 {
        FunctionalRelationshipLocalizationKeyV1.sitePolicyKey(policy)
    }

    static func minimumRequirementLocalizationKey(
        _ boundary: FunctionalRelationshipReadinessBoundaryV1
    ) -> FunctionalRelationshipLocalizationKeyV1 {
        FunctionalRelationshipLocalizationKeyV1.minimumRequirementKey(boundary)
    }
}

typealias ReportFunctionalRelationshipProjectionPolicyV1 =
    ReportFunctionalRelationshipsProjectionPolicyV1

/// C13's report-facing assurance envelope.  The envelope is deliberately a
/// projection value rather than a writer or finalization service: a preview
/// is assembled first, an optional immutable manifest records the exact
/// included/excluded links, and local attestations can bind only to that
/// manifest.  No evidence bytes, actor private detail, or delivery state is
/// represented here.
enum ReportEvidenceAssuranceProjectionPolicyV1 {
    static let sectionID = "evidence-assurance"
    static let sectionVersion = 1
    static let projectionVersion = "report-evidence-assurance-v1"
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let publicationDisposition = "PROVISIONAL_READ_ONLY_PRE_S10"
    static let previewRequired = true
    static let manifestRequiredBeforeAttestation = true
    static let excludesEvidenceContent = true
    static let excludesActorPrivateDetail = true
    static let excludesDeliveryAndRelease = true
    static let supportedFormats: [ReportProjectionFormatV1] = [.openJSON, .structuredText]

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }

    static func evidenceAudience(for audience: ReportAudienceV1) -> EvidenceAudienceV1? {
        switch audience {
        case .internalUse: return .internalReview
        case .customerSafe: return .customerReport
        }
    }
}

/// Exact report binding for C13 preview-first evidence publication.  The
/// visibility rows are carried alongside the links so a consumer cannot
/// silently substitute a different audience decision.  Validation is
/// intentionally explicit about stale snapshot/version/purpose/scope inputs.
struct ReportEvidenceAssuranceProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let publicationDisposition = ReportEvidenceAssuranceProjectionPolicyV1.publicationDisposition

    let schemaVersion: Int
    let audience: EvidenceAudienceV1
    let snapshotSHA256: String
    let projectionVersion: String
    let preview: AssuranceProjectionPreviewV1
    let manifest: AssuranceManifestV1?
    let visibilities: [EvidenceVisibilityV1]
    let attestations: [AttestationV1]
    let omissionCount: Int
    let limitationCodes: [EvidenceLimitationV1]
    let publicationDisposition: String

    init(
        preview: AssuranceProjectionPreviewV1,
        manifest: AssuranceManifestV1? = nil,
        visibilities: [EvidenceVisibilityV1],
        attestations: [AttestationV1] = []
    ) throws {
        try preview.validate()
        let orderedVisibilities = visibilities.sorted {
            $0.visibilityID.uuidString.lowercased() < $1.visibilityID.uuidString.lowercased()
        }
        let orderedAttestations = attestations.sorted {
            $0.attestationID.uuidString.lowercased() < $1.attestationID.uuidString.lowercased()
        }
        let excluded = preview.excludedLinks
        let limitations = Array(Set(excluded.map { $0.decision.limitation }))
            .sorted { $0.rawValue < $1.rawValue }
        schemaVersion = Self.schemaVersion
        audience = preview.audience
        snapshotSHA256 = preview.snapshotSHA256
        projectionVersion = preview.projectionVersion
        self.preview = preview
        self.manifest = manifest
        self.visibilities = orderedVisibilities
        self.attestations = orderedAttestations
        omissionCount = excluded.count
        limitationCodes = limitations
        publicationDisposition = Self.publicationDisposition
        try validate()
    }

    func validate(
        expectedSnapshotSHA256: String? = nil,
        expectedProjectionVersion: String? = nil,
        expectedAudience: EvidenceAudienceV1? = nil,
        expectedPurpose: AttestationPurposeV1? = nil,
        expectedScope: AttestationScopeV1? = nil
    ) throws {
        guard schemaVersion == Self.schemaVersion,
              publicationDisposition == Self.publicationDisposition,
              KernelCanonicalHashV1.validSHA256(snapshotSHA256),
              SnapshotProjectionValidationV1.validID(projectionVersion),
              snapshotSHA256 == preview.snapshotSHA256,
              projectionVersion == preview.projectionVersion,
              audience == preview.audience,
              omissionCount == preview.excludedLinks.count,
              limitationCodes == Array(Set(preview.excludedLinks.map { $0.decision.limitation }))
                    .sorted(by: { $0.rawValue < $1.rawValue }),
              visibilities == visibilities.sorted(by: {
                  $0.visibilityID.uuidString.lowercased() < $1.visibilityID.uuidString.lowercased()
              }),
              Set(visibilities.map(\.visibilityID)).count == visibilities.count,
              attestations == attestations.sorted(by: {
                  $0.attestationID.uuidString.lowercased() < $1.attestationID.uuidString.lowercased()
              }),
              Set(attestations.map(\.attestationID)).count == attestations.count else {
            throw EvidenceAssuranceFailureV1.digestMismatch
        }
        try preview.validate()
        var visibilityByID: [UUID: EvidenceVisibilityV1] = [:]
        for visibility in visibilities {
            try visibility.validate()
            guard visibility.workspaceID == preview.workspaceID,
                  visibilityByID.updateValue(visibility, forKey: visibility.visibilityID) == nil else {
                throw EvidenceAssuranceFailureV1.duplicateIdentity
            }
        }
        for link in preview.includedLinks + preview.excludedLinks {
            guard let visibility = visibilityByID[link.visibilityID] else {
                throw EvidenceAssuranceFailureV1.visibilityDenied
            }
            try link.validate(visibility: visibility)
        }
        if let manifest {
            try manifest.validateFresh(preview: preview)
            guard manifest.workspaceID == preview.workspaceID,
                  manifest.audience == audience,
                  manifest.snapshotSHA256 == snapshotSHA256,
                  manifest.projectionVersion == projectionVersion else {
                throw EvidenceAssuranceFailureV1.stalePreview
            }
            guard !attestations.isEmpty || ReportEvidenceAssuranceProjectionPolicyV1
                .manifestRequiredBeforeAttestation else {
                throw EvidenceAssuranceFailureV1.invalidValue
            }
            for attestation in attestations {
                try attestation.validate(manifest: manifest)
                if let expectedPurpose, attestation.purpose != expectedPurpose {
                    throw EvidenceAssuranceFailureV1.invalidValue
                }
                if let expectedScope, attestation.scope != expectedScope {
                    throw EvidenceAssuranceFailureV1.invalidValue
                }
            }
        } else if !attestations.isEmpty {
            throw EvidenceAssuranceFailureV1.invalidValue
        }
        if let expectedSnapshotSHA256, expectedSnapshotSHA256 != snapshotSHA256 {
            throw EvidenceAssuranceFailureV1.stalePreview
        }
        if let expectedProjectionVersion, expectedProjectionVersion != projectionVersion {
            throw EvidenceAssuranceFailureV1.stalePreview
        }
        if let expectedAudience, expectedAudience != audience {
            throw EvidenceAssuranceFailureV1.visibilityDenied
        }
    }
}

struct ReportSectionDefinitionV1: Codable, Equatable, Hashable, Sendable {
    let sectionID: String
    let version: Int
    let required: Bool
    let supportedFormats: [ReportProjectionFormatV1]
    let privacyClass: ReportPrivacyClassV1
    let requiresHeading: Bool
    let requiresTextAlternative: Bool
    let order: Int

    init(
        sectionID: String,
        version: Int,
        required: Bool,
        supportedFormats: [ReportProjectionFormatV1],
        privacyClass: ReportPrivacyClassV1,
        requiresHeading: Bool,
        requiresTextAlternative: Bool,
        order: Int
    ) throws {
        guard SnapshotProjectionValidationV1.validID(sectionID), version > 0, order >= 0,
              !supportedFormats.isEmpty,
              supportedFormats == supportedFormats.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(supportedFormats).count == supportedFormats.count else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        self.sectionID = sectionID
        self.version = version
        self.required = required
        self.supportedFormats = supportedFormats
        self.privacyClass = privacyClass
        self.requiresHeading = requiresHeading
        self.requiresTextAlternative = requiresTextAlternative
        self.order = order
    }

    func validate() throws {
        _ = try Self(
            sectionID: sectionID,
            version: version,
            required: required,
            supportedFormats: supportedFormats,
            privacyClass: privacyClass,
            requiresHeading: requiresHeading,
            requiresTextAlternative: requiresTextAlternative,
            order: order
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sectionID, version, required, supportedFormats, privacyClass
        case requiresHeading, requiresTextAlternative, order
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sectionID: values.decode(String.self, forKey: .sectionID),
            version: values.decode(Int.self, forKey: .version),
            required: values.decode(Bool.self, forKey: .required),
            supportedFormats: values.decode([ReportProjectionFormatV1].self, forKey: .supportedFormats),
            privacyClass: values.decode(ReportPrivacyClassV1.self, forKey: .privacyClass),
            requiresHeading: values.decode(Bool.self, forKey: .requiresHeading),
            requiresTextAlternative: values.decode(Bool.self, forKey: .requiresTextAlternative),
            order: values.decode(Int.self, forKey: .order)
        )
    }
}

struct ReportSectionRegistryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let registryID: String
    let registryVersion: Int
    let sections: [ReportSectionDefinitionV1]

    init(registryID: String, registryVersion: Int, sections: [ReportSectionDefinitionV1]) throws {
        guard SnapshotProjectionValidationV1.validID(registryID), registryVersion > 0,
              !sections.isEmpty,
              sections.map(\.order) == Array(0..<sections.count),
              Set(sections.map(\.sectionID)).count == sections.count,
              sections.filter(\.required).map(\.sectionID).contains("identity"),
              sections.filter(\.required).map(\.sectionID).contains("limitations"),
              sections.filter(\.required).map(\.sectionID).contains("provenance"),
              sections.filter(\.required).map(\.sectionID).contains("supersession"),
              sections.filter(\.required).map(\.sectionID).contains("manifest") else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.registryID = registryID
        self.registryVersion = registryVersion
        self.sections = sections
    }

    var requiredSectionIDs: Set<String> { Set(sections.filter(\.required).map(\.sectionID)) }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        try sections.forEach { try $0.validate() }
        _ = try Self(registryID: registryID, registryVersion: registryVersion, sections: sections)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, registryID, registryVersion, sections
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            registryID: values.decode(String.self, forKey: .registryID),
            registryVersion: values.decode(Int.self, forKey: .registryVersion),
            sections: values.decode([ReportSectionDefinitionV1].self, forKey: .sections)
        )
    }
}

struct ReportLayoutProfileV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let profileID: String
    let profileRelease: Int
    let audience: ReportAudienceV1
    let detail: ReportDetailLevelV1
    let sectionIDs: [String]
    let mediaLayout: ReportMediaLayoutV1
    let orientation: ReportOrientationV1
    let localeIdentifier: String
    let unitsProfileID: String
    let displayProfileID: String

    init(
        profileID: String,
        profileRelease: Int,
        audience: ReportAudienceV1,
        detail: ReportDetailLevelV1,
        sectionIDs: [String],
        mediaLayout: ReportMediaLayoutV1,
        orientation: ReportOrientationV1,
        localeIdentifier: String,
        unitsProfileID: String,
        displayProfileID: String,
        registry: ReportSectionRegistryV1
    ) throws {
        guard SnapshotProjectionValidationV1.validID(profileID), profileRelease > 0,
              SnapshotProjectionValidationV1.validText(localeIdentifier), localeIdentifier.utf8.count <= 64,
              SnapshotProjectionValidationV1.validID(unitsProfileID),
              SnapshotProjectionValidationV1.validID(displayProfileID),
              Set(sectionIDs).count == sectionIDs.count,
              registry.requiredSectionIDs.isSubset(of: Set(sectionIDs)),
              sectionIDs.allSatisfy({ id in registry.sections.contains(where: { $0.sectionID == id }) }),
              sectionIDs == registry.sections.filter({ sectionIDs.contains($0.sectionID) }).map(\.sectionID) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        if audience == .customerSafe,
           sectionIDs.contains(where: { id in registry.sections.first(where: { $0.sectionID == id })?.privacyClass == .internalOnly }) {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        schemaVersion = Self.schemaVersion
        self.profileID = profileID
        self.profileRelease = profileRelease
        self.audience = audience
        self.detail = detail
        self.sectionIDs = sectionIDs
        self.mediaLayout = mediaLayout
        self.orientation = orientation
        self.localeIdentifier = localeIdentifier
        self.unitsProfileID = unitsProfileID
        self.displayProfileID = displayProfileID
    }

    func validate(against registry: ReportSectionRegistryV1) throws {
        guard schemaVersion == Self.schemaVersion else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        try registry.validate()
        _ = try Self(
            profileID: profileID,
            profileRelease: profileRelease,
            audience: audience,
            detail: detail,
            sectionIDs: sectionIDs,
            mediaLayout: mediaLayout,
            orientation: orientation,
            localeIdentifier: localeIdentifier,
            unitsProfileID: unitsProfileID,
            displayProfileID: displayProfileID,
            registry: registry
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, profileID, profileRelease, audience, detail, sectionIDs
        case mediaLayout, orientation, localeIdentifier, unitsProfileID, displayProfileID
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        let profileID = try values.decode(String.self, forKey: .profileID)
        let profileRelease = try values.decode(Int.self, forKey: .profileRelease)
        let sectionIDs = try values.decode([String].self, forKey: .sectionIDs)
        let localeIdentifier = try values.decode(String.self, forKey: .localeIdentifier)
        let unitsProfileID = try values.decode(String.self, forKey: .unitsProfileID)
        let displayProfileID = try values.decode(String.self, forKey: .displayProfileID)
        guard SnapshotProjectionValidationV1.validID(profileID), profileRelease > 0,
              SnapshotProjectionValidationV1.validText(localeIdentifier), localeIdentifier.utf8.count <= 64,
              SnapshotProjectionValidationV1.validID(unitsProfileID),
              SnapshotProjectionValidationV1.validID(displayProfileID),
              Set(sectionIDs).count == sectionIDs.count,
              sectionIDs.allSatisfy(SnapshotProjectionValidationV1.validID) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.profileID = profileID
        self.profileRelease = profileRelease
        audience = try values.decode(ReportAudienceV1.self, forKey: .audience)
        detail = try values.decode(ReportDetailLevelV1.self, forKey: .detail)
        self.sectionIDs = sectionIDs
        mediaLayout = try values.decode(ReportMediaLayoutV1.self, forKey: .mediaLayout)
        orientation = try values.decode(ReportOrientationV1.self, forKey: .orientation)
        self.localeIdentifier = localeIdentifier
        self.unitsProfileID = unitsProfileID
        self.displayProfileID = displayProfileID
    }
}

struct ExportProfileV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let exportProfileID: String
    let exportProfileRelease: Int
    let formats: [ReportProjectionFormatV1]
    let packaging: ReportPackagingV1
    let privacyTransformID: String
    let maximumMediaItems: Int
    let maximumArchiveBytes: Int64

    init(
        exportProfileID: String,
        exportProfileRelease: Int,
        formats: [ReportProjectionFormatV1],
        packaging: ReportPackagingV1,
        privacyTransformID: String,
        maximumMediaItems: Int,
        maximumArchiveBytes: Int64
    ) throws {
        guard SnapshotProjectionValidationV1.validID(exportProfileID), exportProfileRelease > 0,
              !formats.isEmpty, formats == formats.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(formats).count == formats.count,
              formats.contains(.pdf), formats.contains(.openJSON), formats.contains(.structuredText),
              SnapshotProjectionValidationV1.validID(privacyTransformID),
              (0...256).contains(maximumMediaItems),
              (1...Int64(SnapshotProjectionLimitsV1.maximumProjectionBytes)).contains(maximumArchiveBytes) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.exportProfileID = exportProfileID
        self.exportProfileRelease = exportProfileRelease
        self.formats = formats
        self.packaging = packaging
        self.privacyTransformID = privacyTransformID
        self.maximumMediaItems = maximumMediaItems
        self.maximumArchiveBytes = maximumArchiveBytes
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        _ = try Self(
            exportProfileID: exportProfileID,
            exportProfileRelease: exportProfileRelease,
            formats: formats,
            packaging: packaging,
            privacyTransformID: privacyTransformID,
            maximumMediaItems: maximumMediaItems,
            maximumArchiveBytes: maximumArchiveBytes
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, exportProfileID, exportProfileRelease, formats, packaging
        case privacyTransformID, maximumMediaItems, maximumArchiveBytes
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            exportProfileID: values.decode(String.self, forKey: .exportProfileID),
            exportProfileRelease: values.decode(Int.self, forKey: .exportProfileRelease),
            formats: values.decode([ReportProjectionFormatV1].self, forKey: .formats),
            packaging: values.decode(ReportPackagingV1.self, forKey: .packaging),
            privacyTransformID: values.decode(String.self, forKey: .privacyTransformID),
            maximumMediaItems: values.decode(Int.self, forKey: .maximumMediaItems),
            maximumArchiveBytes: values.decode(Int64.self, forKey: .maximumArchiveBytes)
        )
    }
}

struct FinalizedReportProfileBindingV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: String
    let snapshotID: String
    let outputScopeID: String
    let reportProfileID: String
    let reportProfileRelease: Int
    let reportProfileSHA256: String
    let exportProfileID: String
    let exportProfileRelease: Int
    let exportProfileSHA256: String
    let sectionRegistryID: String
    let sectionRegistryVersion: Int
    let sectionRegistrySHA256: String
    let contractManifestID: String
    let contractManifestVersion: Int
    let contractManifestSHA256: String
    let sectionIDs: [String]
    let audience: ReportAudienceV1
    let detail: ReportDetailLevelV1
    let privacyTransformID: String
    let localeIdentifier: String
    let unitsProfileID: String
    let displayProfileID: String
    let orientation: ReportOrientationV1
    let mediaLayout: ReportMediaLayoutV1
    let rendererVersion: String
    let projectionVersion: String

    init(
        workspaceID: String,
        snapshotID: String,
        outputScopeID: String,
        reportProfileID: String,
        reportProfileRelease: Int,
        reportProfileSHA256: String,
        exportProfileID: String,
        exportProfileRelease: Int,
        exportProfileSHA256: String,
        sectionRegistryID: String,
        sectionRegistryVersion: Int,
        sectionRegistrySHA256: String,
        contractManifestID: String,
        contractManifestVersion: Int,
        contractManifestSHA256: String,
        sectionIDs: [String],
        audience: ReportAudienceV1,
        detail: ReportDetailLevelV1,
        privacyTransformID: String,
        localeIdentifier: String,
        unitsProfileID: String,
        displayProfileID: String,
        orientation: ReportOrientationV1,
        mediaLayout: ReportMediaLayoutV1,
        rendererVersion: String,
        projectionVersion: String
    ) throws {
        let ids = [workspaceID, snapshotID, outputScopeID, reportProfileID, exportProfileID,
                   sectionRegistryID, contractManifestID, privacyTransformID, unitsProfileID,
                   displayProfileID, rendererVersion, projectionVersion]
        guard ids.allSatisfy(SnapshotProjectionValidationV1.validID),
              reportProfileRelease > 0, exportProfileRelease > 0, sectionRegistryVersion > 0,
              contractManifestVersion > 0,
              [reportProfileSHA256, exportProfileSHA256, sectionRegistrySHA256, contractManifestSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),
              !sectionIDs.isEmpty, Set(sectionIDs).count == sectionIDs.count,
              sectionIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              SnapshotProjectionValidationV1.validText(localeIdentifier), localeIdentifier.utf8.count <= 64 else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.snapshotID = snapshotID
        self.outputScopeID = outputScopeID
        self.reportProfileID = reportProfileID
        self.reportProfileRelease = reportProfileRelease
        self.reportProfileSHA256 = reportProfileSHA256
        self.exportProfileID = exportProfileID
        self.exportProfileRelease = exportProfileRelease
        self.exportProfileSHA256 = exportProfileSHA256
        self.sectionRegistryID = sectionRegistryID
        self.sectionRegistryVersion = sectionRegistryVersion
        self.sectionRegistrySHA256 = sectionRegistrySHA256
        self.contractManifestID = contractManifestID
        self.contractManifestVersion = contractManifestVersion
        self.contractManifestSHA256 = contractManifestSHA256
        self.sectionIDs = sectionIDs
        self.audience = audience
        self.detail = detail
        self.privacyTransformID = privacyTransformID
        self.localeIdentifier = localeIdentifier
        self.unitsProfileID = unitsProfileID
        self.displayProfileID = displayProfileID
        self.orientation = orientation
        self.mediaLayout = mediaLayout
        self.rendererVersion = rendererVersion
        self.projectionVersion = projectionVersion
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        _ = try Self(
            workspaceID: workspaceID,
            snapshotID: snapshotID,
            outputScopeID: outputScopeID,
            reportProfileID: reportProfileID,
            reportProfileRelease: reportProfileRelease,
            reportProfileSHA256: reportProfileSHA256,
            exportProfileID: exportProfileID,
            exportProfileRelease: exportProfileRelease,
            exportProfileSHA256: exportProfileSHA256,
            sectionRegistryID: sectionRegistryID,
            sectionRegistryVersion: sectionRegistryVersion,
            sectionRegistrySHA256: sectionRegistrySHA256,
            contractManifestID: contractManifestID,
            contractManifestVersion: contractManifestVersion,
            contractManifestSHA256: contractManifestSHA256,
            sectionIDs: sectionIDs,
            audience: audience,
            detail: detail,
            privacyTransformID: privacyTransformID,
            localeIdentifier: localeIdentifier,
            unitsProfileID: unitsProfileID,
            displayProfileID: displayProfileID,
            orientation: orientation,
            mediaLayout: mediaLayout,
            rendererVersion: rendererVersion,
            projectionVersion: projectionVersion
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, snapshotID, outputScopeID, reportProfileID, reportProfileRelease
        case reportProfileSHA256, exportProfileID, exportProfileRelease, exportProfileSHA256
        case sectionRegistryID, sectionRegistryVersion, sectionRegistrySHA256, contractManifestID
        case contractManifestVersion, contractManifestSHA256, sectionIDs, audience, detail, privacyTransformID
        case localeIdentifier, unitsProfileID, displayProfileID, orientation, mediaLayout, rendererVersion, projectionVersion
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            workspaceID: values.decode(String.self, forKey: .workspaceID),
            snapshotID: values.decode(String.self, forKey: .snapshotID),
            outputScopeID: values.decode(String.self, forKey: .outputScopeID),
            reportProfileID: values.decode(String.self, forKey: .reportProfileID),
            reportProfileRelease: values.decode(Int.self, forKey: .reportProfileRelease),
            reportProfileSHA256: values.decode(String.self, forKey: .reportProfileSHA256),
            exportProfileID: values.decode(String.self, forKey: .exportProfileID),
            exportProfileRelease: values.decode(Int.self, forKey: .exportProfileRelease),
            exportProfileSHA256: values.decode(String.self, forKey: .exportProfileSHA256),
            sectionRegistryID: values.decode(String.self, forKey: .sectionRegistryID),
            sectionRegistryVersion: values.decode(Int.self, forKey: .sectionRegistryVersion),
            sectionRegistrySHA256: values.decode(String.self, forKey: .sectionRegistrySHA256),
            contractManifestID: values.decode(String.self, forKey: .contractManifestID),
            contractManifestVersion: values.decode(Int.self, forKey: .contractManifestVersion),
            contractManifestSHA256: values.decode(String.self, forKey: .contractManifestSHA256),
            sectionIDs: values.decode([String].self, forKey: .sectionIDs),
            audience: values.decode(ReportAudienceV1.self, forKey: .audience),
            detail: values.decode(ReportDetailLevelV1.self, forKey: .detail),
            privacyTransformID: values.decode(String.self, forKey: .privacyTransformID),
            localeIdentifier: values.decode(String.self, forKey: .localeIdentifier),
            unitsProfileID: values.decode(String.self, forKey: .unitsProfileID),
            displayProfileID: values.decode(String.self, forKey: .displayProfileID),
            orientation: values.decode(ReportOrientationV1.self, forKey: .orientation),
            mediaLayout: values.decode(ReportMediaLayoutV1.self, forKey: .mediaLayout),
            rendererVersion: values.decode(String.self, forKey: .rendererVersion),
            projectionVersion: values.decode(String.self, forKey: .projectionVersion)
        )
    }
}

struct ReportPreviewProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let previewID: String
    let sourceRevision: Int
    let profileSHA256: String
    let markedPreview: Bool
    let hasReportEffect: Bool
    let hasMetricEffect: Bool
    let hasShareEffect: Bool

    init(previewID: String, sourceRevision: Int, profileSHA256: String) throws {
        guard SnapshotProjectionValidationV1.validID(previewID), sourceRevision > 0,
              KernelCanonicalHashV1.validSHA256(profileSHA256) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.previewID = previewID
        self.sourceRevision = sourceRevision
        self.profileSHA256 = profileSHA256
        markedPreview = true
        hasReportEffect = false
        hasMetricEffect = false
        hasShareEffect = false
    }

    func isStale(currentSourceRevision: Int, currentProfileSHA256: String) -> Bool {
        sourceRevision != currentSourceRevision || profileSHA256 != currentProfileSHA256
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        _ = try Self(previewID: previewID, sourceRevision: sourceRevision, profileSHA256: profileSHA256)
        guard markedPreview, !hasReportEffect, !hasMetricEffect, !hasShareEffect else {
            throw SnapshotProjectionFailureV1.partialEffect
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, previewID, sourceRevision, profileSHA256, markedPreview
        case hasReportEffect, hasMetricEffect, hasShareEffect
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        let reconstructed = try Self(
            previewID: values.decode(String.self, forKey: .previewID),
            sourceRevision: values.decode(Int.self, forKey: .sourceRevision),
            profileSHA256: values.decode(String.self, forKey: .profileSHA256)
        )
        guard try values.decode(Bool.self, forKey: .markedPreview) == reconstructed.markedPreview,
              values.decode(Bool.self, forKey: .hasReportEffect) == reconstructed.hasReportEffect,
              values.decode(Bool.self, forKey: .hasMetricEffect) == reconstructed.hasMetricEffect,
              values.decode(Bool.self, forKey: .hasShareEffect) == reconstructed.hasShareEffect else {
            throw SnapshotProjectionFailureV1.partialEffect
        }
        self = reconstructed
    }
}

struct OutputScopedContentReferenceV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let outputScopeID: String
    let outputReferenceID: String
    let workspaceBindingSHA256: String
    let contentSHA256: String
    let mediaType: String
    let byteRole: ContentByteRoleV1

    static func < (lhs: OutputScopedContentReferenceV1, rhs: OutputScopedContentReferenceV1) -> Bool {
        lhs.outputReferenceID < rhs.outputReferenceID
    }

    init(outputScopeID: String, ordinal: Int, reference: ContentReferenceV1) throws {
        guard SnapshotProjectionValidationV1.validID(outputScopeID),
              (0...999).contains(ordinal),
              let sha256 = reference.digests.digest(for: .sha256)?.hexadecimalValue else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        let workspaceBindingSHA256 = KernelCanonicalHashV1.sha256(
            Data("\(reference.workspaceID)|\(outputScopeID)".utf8)
        )
        let namespace = KernelCanonicalHashV1.sha256(Data("\(reference.workspaceID)|\(outputScopeID)|\(sha256)".utf8))
        self.outputScopeID = outputScopeID
        outputReferenceID = "out-\(namespace.prefix(16))-\(String(format: "%03d", ordinal))"
        self.workspaceBindingSHA256 = workspaceBindingSHA256
        contentSHA256 = sha256
        mediaType = reference.mediaType
        byteRole = reference.byteRole
    }

    func validate() throws {
        let identity = Array(outputReferenceID.utf8)
        let lowercaseHex = identity.dropFirst(4).prefix(16)
        let ordinal = identity.suffix(3)
        guard SnapshotProjectionValidationV1.validID(outputScopeID),
              identity.count == 24,
              identity.starts(with: Array("out-".utf8)),
              identity[20] == 0x2D,
              lowercaseHex.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }),
              ordinal.allSatisfy({ (0x30...0x39).contains($0) }),
              KernelCanonicalHashV1.validSHA256(workspaceBindingSHA256),
              KernelCanonicalHashV1.validSHA256(contentSHA256),
              ContentContractValidationV1.validMediaType(mediaType) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case outputScopeID, outputReferenceID, workspaceBindingSHA256, contentSHA256, mediaType, byteRole
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        outputScopeID = try values.decode(String.self, forKey: .outputScopeID)
        outputReferenceID = try values.decode(String.self, forKey: .outputReferenceID)
        workspaceBindingSHA256 = try values.decode(String.self, forKey: .workspaceBindingSHA256)
        contentSHA256 = try values.decode(String.self, forKey: .contentSHA256)
        mediaType = try values.decode(String.self, forKey: .mediaType)
        byteRole = try values.decode(ContentByteRoleV1.self, forKey: .byteRole)
        try validate()
    }
}

// MARK: - C14 inspection review projection

/// C14's report section is a typed, read-only history projection.  Reasons,
/// actor snapshots, private assignment details, and evidence content remain
/// out of this public semantic surface; exact facts and their digests stay
/// available in the completed-snapshot contract.
enum ReportInspectionReviewHistoryProjectionPolicyV1 {
    static let sectionID = "inspection-review-history"
    static let sectionVersion = 1
    static let projectionVersion = "report-inspection-review-history-v1"
    static let requiredTypedLabels = true
    static let excludesClaims = true
    static let excludesTelemetry = true
    static let excludesOwnershipAndAuthorization = true
    static let excludesActorPrivateDetail = true
    static let supportsOpenJSON = true
    static let supportsStructuredText = true

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        switch format {
        case .openJSON, .structuredText: return true
        default: return false
        }
    }
}

struct ReportInspectionReviewHistoryProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let projectionVersion: String
    let sourceSnapshotSHA256: String
    let historySnapshotSHA256: String
    let bindingSHA256: String
    let reviewTransitionIDs: [String]
    let reviewStateLabels: [String]
    let reviewDispositionIDs: [String]
    let reviewDispositionLabels: [String]
    let changeRequestRevisionIDs: [String]
    let changeStateLabels: [String]
    let actionEventIDs: [String]
    let actionStateLabels: [String]

    var reviewCount: Int { reviewTransitionIDs.count + reviewDispositionIDs.count }
    var changeCount: Int { changeRequestRevisionIDs.count }
    var actionCount: Int { actionEventIDs.count }

    init(history: CompletedInspectionReviewHistorySnapshotV1) throws {
        try history.validate()
        schemaVersion = Self.schemaVersion
        projectionVersion = ReportInspectionReviewHistoryProjectionPolicyV1.projectionVersion
        sourceSnapshotSHA256 = history.sourceSnapshotSHA256
        historySnapshotSHA256 = history.snapshotSHA256
        bindingSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            projectionVersion: projectionVersion,
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            historySnapshotSHA256: historySnapshotSHA256,
            reviewTransitionIDs: history.reviewTransitions.map { $0.transitionID.uuidString.lowercased() },
            reviewStateLabels: history.reviewTransitions.map { $0.toState.rawValue },
            reviewDispositionIDs: history.reviewDispositions.map { $0.dispositionID.uuidString.lowercased() },
            reviewDispositionLabels: history.reviewDispositions.map { $0.kind.rawValue },
            changeRequestRevisionIDs: history.changeRequests.map { $0.requestRevisionID.uuidString.lowercased() },
            changeStateLabels: history.changeRequests.map { $0.state.rawValue },
            actionEventIDs: history.correctiveActions.map { $0.eventID.uuidString.lowercased() },
            actionStateLabels: history.correctiveActions.map { $0.state.rawValue }
        ))
        reviewTransitionIDs = history.reviewTransitions.map { $0.transitionID.uuidString.lowercased() }
        reviewStateLabels = history.reviewTransitions.map { $0.toState.rawValue }
        reviewDispositionIDs = history.reviewDispositions.map { $0.dispositionID.uuidString.lowercased() }
        reviewDispositionLabels = history.reviewDispositions.map { $0.kind.rawValue }
        changeRequestRevisionIDs = history.changeRequests.map { $0.requestRevisionID.uuidString.lowercased() }
        changeStateLabels = history.changeRequests.map { $0.state.rawValue }
        actionEventIDs = history.correctiveActions.map { $0.eventID.uuidString.lowercased() }
        actionStateLabels = history.correctiveActions.map { $0.state.rawValue }
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              projectionVersion == ReportInspectionReviewHistoryProjectionPolicyV1.projectionVersion,
              KernelCanonicalHashV1.validSHA256(sourceSnapshotSHA256),
              KernelCanonicalHashV1.validSHA256(historySnapshotSHA256),
              KernelCanonicalHashV1.validSHA256(bindingSHA256),
              reviewTransitionIDs.count == reviewStateLabels.count,
              reviewDispositionIDs.count == reviewDispositionLabels.count,
              changeRequestRevisionIDs.count == changeStateLabels.count,
              actionEventIDs.count == actionStateLabels.count,
              reviewTransitionIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              reviewDispositionIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              changeRequestRevisionIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              actionEventIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              reviewTransitionIDs == reviewTransitionIDs.sorted(),
              reviewDispositionIDs == reviewDispositionIDs.sorted(),
              changeRequestRevisionIDs == changeRequestRevisionIDs.sorted(),
              actionEventIDs == actionEventIDs.sorted(),
              Set(reviewTransitionIDs).count == reviewTransitionIDs.count,
              Set(reviewDispositionIDs).count == reviewDispositionIDs.count,
              Set(changeRequestRevisionIDs).count == changeRequestRevisionIDs.count,
              Set(actionEventIDs).count == actionEventIDs.count,
              reviewStateLabels.allSatisfy(SnapshotProjectionValidationV1.validText),
              reviewDispositionLabels.allSatisfy(SnapshotProjectionValidationV1.validText),
              changeStateLabels.allSatisfy(SnapshotProjectionValidationV1.validText),
              actionStateLabels.allSatisfy(SnapshotProjectionValidationV1.validText) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        let expected = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: schemaVersion,
            projectionVersion: projectionVersion,
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            historySnapshotSHA256: historySnapshotSHA256,
            reviewTransitionIDs: reviewTransitionIDs,
            reviewStateLabels: reviewStateLabels,
            reviewDispositionIDs: reviewDispositionIDs,
            reviewDispositionLabels: reviewDispositionLabels,
            changeRequestRevisionIDs: changeRequestRevisionIDs,
            changeStateLabels: changeStateLabels,
            actionEventIDs: actionEventIDs,
            actionStateLabels: actionStateLabels
        ))
        guard bindingSHA256 == expected else { throw SnapshotProjectionFailureV1.digestMismatch }
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let projectionVersion: String
        let sourceSnapshotSHA256: String
        let historySnapshotSHA256: String
        let reviewTransitionIDs: [String]
        let reviewStateLabels: [String]
        let reviewDispositionIDs: [String]
        let reviewDispositionLabels: [String]
        let changeRequestRevisionIDs: [String]
        let changeStateLabels: [String]
        let actionEventIDs: [String]
        let actionStateLabels: [String]
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, projectionVersion, sourceSnapshotSHA256
        case historySnapshotSHA256, bindingSHA256, reviewTransitionIDs
        case reviewStateLabels, reviewDispositionIDs, reviewDispositionLabels
        case changeRequestRevisionIDs, changeStateLabels, actionEventIDs
        case actionStateLabels
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // The projection's public wire form is deliberately decoded directly;
        // no private actor/reason data is needed to validate a report copy.
        self.schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        self.projectionVersion = try values.decode(String.self, forKey: .projectionVersion)
        self.sourceSnapshotSHA256 = try values.decode(String.self, forKey: .sourceSnapshotSHA256)
        self.historySnapshotSHA256 = try values.decode(String.self, forKey: .historySnapshotSHA256)
        self.bindingSHA256 = try values.decode(String.self, forKey: .bindingSHA256)
        self.reviewTransitionIDs = try values.decode([String].self, forKey: .reviewTransitionIDs)
        self.reviewStateLabels = try values.decode([String].self, forKey: .reviewStateLabels)
        self.reviewDispositionIDs = try values.decode([String].self, forKey: .reviewDispositionIDs)
        self.reviewDispositionLabels = try values.decode([String].self, forKey: .reviewDispositionLabels)
        self.changeRequestRevisionIDs = try values.decode([String].self, forKey: .changeRequestRevisionIDs)
        self.changeStateLabels = try values.decode([String].self, forKey: .changeStateLabels)
        self.actionEventIDs = try values.decode([String].self, forKey: .actionEventIDs)
        self.actionStateLabels = try values.decode([String].self, forKey: .actionStateLabels)
        try validate()
    }
}

typealias ReportReviewChangeActionHistoryProjectionV1 = ReportInspectionReviewHistoryProjectionV1

// MARK: - C15 work-packet report projection

/// C15 exposes only bounded, customer-safe packet coordination facts. The
/// canonical packet event rows, actor snapshots, result/evidence links, and
/// collision digests remain in the completed snapshot and are never copied to
/// this report DTO.
enum ReportWorkPacketProjectionPolicyV1 {
    static let sectionID = "work-packet"
    static let sectionVersion = 1
    static let projectionVersion = "report-work-packet-v1"
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let publicationDisposition = "PROVISIONAL_READ_ONLY_PRE_S10"
    static let requiredTypedLabels = true
    static let indexesCurrentHeadsOnly = true
    static let excludesActorPrivateDetail = true
    static let excludesResultAndEvidenceLinks = true
    static let excludesClaimsAndAuthorization = true
    static let excludesTelemetryAndDelivery = true
    static let supportedFormats: [ReportProjectionFormatV1] = [.openJSON, .structuredText]

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }
}

struct ReportWorkPacketProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let projectionVersion: String
    let sourceSnapshotSHA256: String
    let packetID: UUID
    let manifestSHA256: String
    let itemCount: Int
    let itemIDs: [String]
    let itemStateLabels: [String]
    let preservedResultCount: Int
    let collisionCount: Int
    let historyEventCount: Int
    let bindingSHA256: String

    init(
        snapshot: CompletedWorkPacketSnapshotV1,
        sourceSnapshotSHA256: String
    ) throws {
        try snapshot.validate()
        guard KernelCanonicalHashV1.validSHA256(sourceSnapshotSHA256) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        let ordered = snapshot.items.sorted { $0.itemID < $1.itemID }
        let ids = ordered.map(\.itemID)
        let states = ordered.map(\.state.rawValue)
        let resultCount = ordered.reduce(0) { $0 + $1.preservedResultCount }
        let collisionCount = ordered.reduce(0) { $0 + $1.conflictKinds.count }
        let historyCount = snapshot.claims.count + snapshot.leases.count
            + snapshot.releases.count + snapshot.handoffs.count
        let binding = try Self.binding(
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            packetID: snapshot.manifest.packetID,
            manifestSHA256: snapshot.manifest.manifestSHA256,
            itemCount: ordered.count,
            itemIDs: ids,
            itemStateLabels: states,
            preservedResultCount: resultCount,
            collisionCount: collisionCount,
            historyEventCount: historyCount
        )
        self.init(
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            packetID: snapshot.manifest.packetID,
            manifestSHA256: snapshot.manifest.manifestSHA256,
            itemCount: ordered.count,
            itemIDs: ids,
            itemStateLabels: states,
            preservedResultCount: resultCount,
            collisionCount: collisionCount,
            historyEventCount: historyCount,
            bindingSHA256: binding
        )
    }

    private init(
        sourceSnapshotSHA256: String,
        packetID: UUID,
        manifestSHA256: String,
        itemCount: Int,
        itemIDs: [String],
        itemStateLabels: [String],
        preservedResultCount: Int,
        collisionCount: Int,
        historyEventCount: Int,
        bindingSHA256: String
    ) {
        schemaVersion = Self.schemaVersion
        projectionVersion = ReportWorkPacketProjectionPolicyV1.projectionVersion
        self.sourceSnapshotSHA256 = sourceSnapshotSHA256
        self.packetID = packetID
        self.manifestSHA256 = manifestSHA256
        self.itemCount = itemCount
        self.itemIDs = itemIDs
        self.itemStateLabels = itemStateLabels
        self.preservedResultCount = preservedResultCount
        self.collisionCount = collisionCount
        self.historyEventCount = historyEventCount
        self.bindingSHA256 = bindingSHA256
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              projectionVersion == ReportWorkPacketProjectionPolicyV1.projectionVersion,
              KernelCanonicalHashV1.validSHA256(sourceSnapshotSHA256),
              packetID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              KernelCanonicalHashV1.validSHA256(manifestSHA256),
              itemCount > 0,
              itemIDs.count == itemCount,
              itemStateLabels.count == itemCount,
              itemIDs == itemIDs.sorted(),
              Set(itemIDs).count == itemIDs.count,
              itemIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              itemStateLabels.allSatisfy {
                  CompletedWorkPacketItemStateV1(rawValue: $0) != nil
              },
              preservedResultCount >= 0,
              collisionCount >= 0,
              historyEventCount >= 0,
              KernelCanonicalHashV1.validSHA256(bindingSHA256) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        let expected = try Self.binding(
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            packetID: packetID,
            manifestSHA256: manifestSHA256,
            itemCount: itemCount,
            itemIDs: itemIDs,
            itemStateLabels: itemStateLabels,
            preservedResultCount: preservedResultCount,
            collisionCount: collisionCount,
            historyEventCount: historyEventCount
        )
        guard expected == bindingSHA256 else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
    }

    private static func binding(
        sourceSnapshotSHA256: String,
        packetID: UUID,
        manifestSHA256: String,
        itemCount: Int,
        itemIDs: [String],
        itemStateLabels: [String],
        preservedResultCount: Int,
        collisionCount: Int,
        historyEventCount: Int
    ) throws -> String {
        KernelCanonicalHashV1.sha256(try WorkspaceMutationCanonicalV1.data(Basis(
            schemaVersion: Self.schemaVersion,
            projectionVersion: ReportWorkPacketProjectionPolicyV1.projectionVersion,
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            packetID: packetID,
            manifestSHA256: manifestSHA256,
            itemCount: itemCount,
            itemIDs: itemIDs,
            itemStateLabels: itemStateLabels,
            preservedResultCount: preservedResultCount,
            collisionCount: collisionCount,
            historyEventCount: historyEventCount
        )))
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let projectionVersion: String
        let sourceSnapshotSHA256: String
        let packetID: UUID
        let manifestSHA256: String
        let itemCount: Int
        let itemIDs: [String]
        let itemStateLabels: [String]
        let preservedResultCount: Int
        let collisionCount: Int
        let historyEventCount: Int
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, projectionVersion, sourceSnapshotSHA256, packetID
        case manifestSHA256, itemCount, itemIDs, itemStateLabels
        case preservedResultCount, collisionCount, historyEventCount, bindingSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sourceSnapshotSHA256: values.decode(String.self, forKey: .sourceSnapshotSHA256),
            packetID: values.decode(UUID.self, forKey: .packetID),
            manifestSHA256: values.decode(String.self, forKey: .manifestSHA256),
            itemCount: values.decode(Int.self, forKey: .itemCount),
            itemIDs: values.decode([String].self, forKey: .itemIDs),
            itemStateLabels: values.decode([String].self, forKey: .itemStateLabels),
            preservedResultCount: values.decode(Int.self, forKey: .preservedResultCount),
            collisionCount: values.decode(Int.self, forKey: .collisionCount),
            historyEventCount: values.decode(Int.self, forKey: .historyEventCount),
            bindingSHA256: values.decode(String.self, forKey: .bindingSHA256)
        )
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try values.decode(String.self, forKey: .projectionVersion)
                    == ReportWorkPacketProjectionPolicyV1.projectionVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try validate()
    }
}

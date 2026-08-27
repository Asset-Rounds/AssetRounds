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

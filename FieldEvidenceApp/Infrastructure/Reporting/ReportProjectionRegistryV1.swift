import Foundation

enum GuidedSurveyReportProjectionRegistryV1 {
    static func projection(
        publication: SurveyPublicationSnapshotV1
    ) throws -> SurveyPublicationReportProjectionV1 {
        try SurveyPublicationReportProjectionV1(publication: publication)
    }
}

enum IntegrationProjectionReportExclusionV1 {
    static func validate() throws {
        let coverage = IntegrationEventJournalCoverageV1()
        try coverage.validate()
        guard !coverage.reportSourceOfTruth,
              !IntegrationProjectionSchemaV1.canonicalReportSource else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
    }
}

enum AccessibleDocumentProjectionRegistryV1{
    static let semanticTreeFamily="AccessibleDocumentSemanticTreeV1"
    static let persistence="DERIVED_ONLY"
    static let source="REPORT_SEMANTIC_PROJECTION_V1"
    static func build(snapshot:CompletedActivitySnapshotV1,projection:ReportSemanticProjectionV1,manifest:ContractManifestV1,layoutProfile:ReportLayoutProfileV1,workspaceID:WorkspaceID,brandProfileID:String,brandProfileRelease:Int,brandProfileSHA256:String,evidenceReferences:[OutputScopedContentReferenceV1]=[])throws->AccessibleDocumentSemanticTreeV1{try AccessibleDocumentReportSemanticTreeBuilderV1.build(snapshot:snapshot,projection:projection,manifest:manifest,layoutProfile:layoutProfile,workspaceID:workspaceID,brandProfileID:brandProfileID,brandProfileRelease:brandProfileRelease,brandProfileSHA256:brandProfileSHA256,evidenceReferences:evidenceReferences)}
}

enum ReportProjectionPublicationBoundaryV1: String, CaseIterable, Sendable {
    case beforeValidation = "BEFORE_VALIDATION"
    case afterValidation = "AFTER_VALIDATION"
    case afterSemanticProjection = "AFTER_SEMANTIC_PROJECTION"
    case afterOpenJSON = "AFTER_OPEN_JSON"
    case afterPDF = "AFTER_PDF"
    case afterStructuredText = "AFTER_STRUCTURED_TEXT"
    case afterReopenValidationBeforePublication = "AFTER_REOPEN_VALIDATION_BEFORE_PUBLICATION"
}

struct ReportProjectionBundleV1: Equatable, Sendable {
    let snapshotID: String
    let snapshotSHA256: String
    let semanticProjection: ReportSemanticProjectionV1
    let pdf: ReportProjectionOutputV1
    let openJSON: ReportProjectionOutputV1
    let structuredText: ReportProjectionOutputV1
    let artifactSetSHA256: String
    let accessibleStructuredTextAlwaysPresent: Bool
    let taggedPDFAccessibilityClaimed: Bool
    let requiresFinalAudienceConfirmation: Bool
    let externalPublicationAuthorized: Bool

    init(
        snapshot: CompletedActivitySnapshotV1,
        semanticProjection: ReportSemanticProjectionV1,
        pdf: ReportProjectionOutputV1,
        openJSON: ReportProjectionOutputV1,
        structuredText: ReportProjectionOutputV1
    ) throws {
        try self.init(
            snapshotID: snapshot.payload.snapshotID,
            snapshotSHA256: snapshot.snapshotSHA256,
            audience: snapshot.payload.profileBinding.audience,
            semanticProjection: semanticProjection,
            pdf: pdf,
            openJSON: openJSON,
            structuredText: structuredText
        )
    }

    init(
        snapshot: CompletedActivitySnapshotV2,
        semanticProjection: ReportSemanticProjectionV1,
        pdf: ReportProjectionOutputV1,
        openJSON: ReportProjectionOutputV1,
        structuredText: ReportProjectionOutputV1
    ) throws {
        try self.init(
            snapshotID: snapshot.payload.activity.snapshotID,
            snapshotSHA256: snapshot.snapshotSHA256,
            audience: snapshot.payload.activity.profileBinding.audience,
            semanticProjection: semanticProjection,
            pdf: pdf,
            openJSON: openJSON,
            structuredText: structuredText
        )
    }

    init(
        snapshot: CompletedActivitySnapshotV3,
        semanticProjection: ReportSemanticProjectionV1,
        pdf: ReportProjectionOutputV1,
        openJSON: ReportProjectionOutputV1,
        structuredText: ReportProjectionOutputV1
    ) throws {
        try self.init(
            snapshotID: snapshot.payload.activity.activity.snapshotID,
            snapshotSHA256: snapshot.snapshotSHA256,
            audience: snapshot.payload.activity.activity.profileBinding.audience,
            semanticProjection: semanticProjection,
            pdf: pdf,
            openJSON: openJSON,
            structuredText: structuredText
        )
    }

    init(
        snapshot: CompletedActivitySnapshotV4,
        semanticProjection: ReportSemanticProjectionV1,
        pdf: ReportProjectionOutputV1,
        openJSON: ReportProjectionOutputV1,
        structuredText: ReportProjectionOutputV1
    ) throws {
        try self.init(
            snapshotID: snapshot.payload.activity.activity.activity.snapshotID,
            snapshotSHA256: snapshot.snapshotSHA256,
            audience: snapshot.payload.activity.activity.activity.profileBinding.audience,
            semanticProjection: semanticProjection,
            pdf: pdf,
            openJSON: openJSON,
            structuredText: structuredText
        )
    }

    init(
        snapshot: CompletedActivitySnapshotV5,
        semanticProjection: ReportSemanticProjectionV1,
        pdf: ReportProjectionOutputV1,
        openJSON: ReportProjectionOutputV1,
        structuredText: ReportProjectionOutputV1
    ) throws {
        try self.init(
            snapshotID: snapshot.payload.activity.activity.activity.activity.snapshotID,
            snapshotSHA256: snapshot.snapshotSHA256,
            audience: snapshot.payload.activity.activity.activity.activity.profileBinding.audience,
            semanticProjection: semanticProjection,
            pdf: pdf,
            openJSON: openJSON,
            structuredText: structuredText
        )
    }

    init(
        snapshot: CompletedActivitySnapshotV6,
        semanticProjection: ReportSemanticProjectionV1,
        pdf: ReportProjectionOutputV1,
        openJSON: ReportProjectionOutputV1,
        structuredText: ReportProjectionOutputV1
    ) throws {
        try self.init(
            snapshotID: snapshot.payload.activity.activity.activity.activity.activity.snapshotID,
            snapshotSHA256: snapshot.snapshotSHA256,
            audience: snapshot.payload.activity.activity.activity.activity.activity.profileBinding.audience,
            semanticProjection: semanticProjection,
            pdf: pdf,
            openJSON: openJSON,
            structuredText: structuredText
        )
    }

    private init(
        snapshotID: String,
        snapshotSHA256: String,
        audience: ReportAudienceV1,
        semanticProjection: ReportSemanticProjectionV1,
        pdf: ReportProjectionOutputV1,
        openJSON: ReportProjectionOutputV1,
        structuredText: ReportProjectionOutputV1
    ) throws {
        let outputs = [pdf, openJSON, structuredText]
        guard Set(outputs.map(\.format)) == Set([.pdf, .openJSON, .structuredText]),
              Set(outputs.map(\.semanticSHA256)) == Set([semanticProjection.semanticSHA256]),
              outputs.allSatisfy({ $0.orderedSemanticIDs == semanticProjection.nodes.map(\.semanticID) }),
              outputs.allSatisfy({ KernelCanonicalHashV1.sha256($0.data) == $0.sha256 }),
              !structuredText.data.isEmpty,
              !pdf.taggedPDFAccessibilityEvidence else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        let reopenedOpenJSON = try DeterministicOpenJSONRendererV1.reopen(openJSON.data)
        let reopenedStructuredText = try DeterministicOpenJSONRendererV1.reopenStructuredText(structuredText.data)
        let reopenedPDF = try DeterministicPDFRendererV1.reopen(pdf.data)
        guard reopenedOpenJSON == semanticProjection,
              reopenedStructuredText == semanticProjection,
              reopenedPDF == semanticProjection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        let artifactRows = outputs.sorted(by: { $0.format.rawValue < $1.format.rawValue }).map {
            "\($0.format.rawValue):\($0.sha256):\($0.data.count)"
        }.joined(separator: "\n") + "\n"
        self.snapshotID = snapshotID
        self.snapshotSHA256 = snapshotSHA256
        self.semanticProjection = semanticProjection
        self.pdf = pdf
        self.openJSON = openJSON
        self.structuredText = structuredText
        artifactSetSHA256 = KernelCanonicalHashV1.sha256(Data(artifactRows.utf8))
        accessibleStructuredTextAlwaysPresent = true
        taggedPDFAccessibilityClaimed = false
        requiresFinalAudienceConfirmation = audience == .customerSafe
        externalPublicationAuthorized = false
    }
}

enum ReportProjectionPublicationV1: Equatable, Sendable {
    case zero
    case complete(ReportProjectionBundleV1)
}

struct ReportProjectionRegistryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let registryID = "report-projection-registry-v1"
    static let persistentContractSchema = "KERNEL_SNAPSHOT_V1"
    static let downgradeDisposition = "DORMANT_REVERT_ALLOWED"
    let schemaVersion: Int
    let registryID: String
    let persistentContractSchema: String
    let downgradeDisposition: String
    let soleRenderer: String
    let requiredFormats: [ReportProjectionFormatV1]
    let nativeCompileRan: Bool
    let hostedDispatchRan: Bool
    let adoptionEnabled: Bool
    let acceptanceCredit: Bool
    let releaseCredit: Bool
    let requiresAcceptedS10_6Reconciliation: Bool

    init() {
        schemaVersion = Self.schemaVersion
        registryID = Self.registryID
        persistentContractSchema = Self.persistentContractSchema
        downgradeDisposition = Self.downgradeDisposition
        soleRenderer = ReportSemanticProjectorV1.rendererVersion
        requiredFormats = [.openJSON, .pdf, .structuredText]
        nativeCompileRan = false
        hostedDispatchRan = false
        adoptionEnabled = false
        acceptanceCredit = false
        releaseCredit = false
        requiresAcceptedS10_6Reconciliation = true
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, registryID, persistentContractSchema, downgradeDisposition, soleRenderer
        case requiredFormats, nativeCompileRan, hostedDispatchRan, adoptionEnabled, acceptanceCredit
        case releaseCredit, requiresAcceptedS10_6Reconciliation
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let expected = Self()
        guard try values.decode(Int.self, forKey: .schemaVersion) == expected.schemaVersion,
              try values.decode(String.self, forKey: .registryID) == expected.registryID,
              try values.decode(String.self, forKey: .persistentContractSchema) == expected.persistentContractSchema,
              try values.decode(String.self, forKey: .downgradeDisposition) == expected.downgradeDisposition,
              try values.decode(String.self, forKey: .soleRenderer) == expected.soleRenderer,
              try values.decode([ReportProjectionFormatV1].self, forKey: .requiredFormats) == expected.requiredFormats,
              try values.decode(Bool.self, forKey: .nativeCompileRan) == expected.nativeCompileRan,
              try values.decode(Bool.self, forKey: .hostedDispatchRan) == expected.hostedDispatchRan,
              try values.decode(Bool.self, forKey: .adoptionEnabled) == expected.adoptionEnabled,
              try values.decode(Bool.self, forKey: .acceptanceCredit) == expected.acceptanceCredit,
              try values.decode(Bool.self, forKey: .releaseCredit) == expected.releaseCredit,
              try values.decode(Bool.self, forKey: .requiresAcceptedS10_6Reconciliation)
                == expected.requiresAcceptedS10_6Reconciliation else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        self = expected
    }

    func validate() throws {
        try IntegrationProjectionReportExclusionV1.validate()
        guard self == Self() else { throw SnapshotProjectionFailureV1.incompatibleVersion }
    }

    func render(
        snapshot: CompletedActivitySnapshotV1,
        manifest: ContractManifestV1,
        reportProfile: ReportLayoutProfileV1,
        exportProfile: ExportProfileV1,
        recoveringFrom boundary: ReportProjectionPublicationBoundaryV1? = nil
    ) throws -> ReportProjectionPublicationV1 {
        if boundary == .beforeValidation { return .zero }
        try validate()
        try snapshot.validate()
        try manifest.validate()
        try reportProfile.validate(against: manifest.reportSectionRegistry)
        try exportProfile.validate()
        _ = try CompletedActivitySnapshotCanonicalCodecV1.encode(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let sectionRegistrySHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(manifest.reportSectionRegistry))
        let manifestSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(manifest))
        let reportProfileSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(reportProfile))
        let exportProfileSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(exportProfile))
        let binding = snapshot.payload.profileBinding
        try binding.validate()
        guard sectionRegistrySHA256 == binding.sectionRegistrySHA256,
              manifest.reportSectionRegistry.registryID == binding.sectionRegistryID,
              manifest.reportSectionRegistry.registryVersion == binding.sectionRegistryVersion,
              manifest.manifestID == binding.contractManifestID,
              manifest.manifestVersion == binding.contractManifestVersion,
              manifestSHA256 == binding.contractManifestSHA256,
              reportProfileSHA256 == binding.reportProfileSHA256,
              reportProfile.profileID == binding.reportProfileID,
              reportProfile.profileRelease == binding.reportProfileRelease,
              reportProfile.sectionIDs == binding.sectionIDs,
              reportProfile.audience == binding.audience,
              reportProfile.detail == binding.detail,
              reportProfile.localeIdentifier == binding.localeIdentifier,
              reportProfile.unitsProfileID == binding.unitsProfileID,
              reportProfile.displayProfileID == binding.displayProfileID,
              reportProfile.orientation == binding.orientation,
              reportProfile.mediaLayout == binding.mediaLayout,
              exportProfileSHA256 == binding.exportProfileSHA256,
              exportProfile.exportProfileID == binding.exportProfileID,
              exportProfile.exportProfileRelease == binding.exportProfileRelease,
              exportProfile.privacyTransformID == binding.privacyTransformID,
              Set(requiredFormats).isSubset(of: Set(exportProfile.formats)),
              manifest.reportSectionRegistry.requiredSectionIDs.isSubset(of: Set(binding.sectionIDs)),
              binding.sectionIDs.allSatisfy({ id in
                  manifest.reportSectionRegistry.sections.contains(where: { $0.sectionID == id })
              }),
              binding.sectionIDs.allSatisfy({ id in
                  guard let section = manifest.reportSectionRegistry.sections.first(where: { $0.sectionID == id }) else {
                      return false
                  }
                  return Set(requiredFormats).isSubset(of: Set(section.supportedFormats))
              }),
              binding.rendererVersion == soleRenderer,
              snapshot.payload.evidenceCards.allSatisfy({ $0.audience == binding.audience }) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        if boundary == .afterValidation { return .zero }

        let semantic = try ReportSemanticProjectorV1.project(snapshot: snapshot, manifest: manifest)
        if boundary == .afterSemanticProjection { return .zero }
        let openJSON = try DeterministicOpenJSONRendererV1.render(semantic)
        if boundary == .afterOpenJSON { return .zero }
        let pdf = try DeterministicPDFRendererV1.render(semantic, layoutProfile: reportProfile)
        if boundary == .afterPDF { return .zero }
        let text = try DeterministicOpenJSONRendererV1.renderStructuredText(semantic)
        if boundary == .afterStructuredText || boundary == .afterReopenValidationBeforePublication { return .zero }

        let renderedBytes = [openJSON, pdf, text].reduce(Int64(0)) { partial, output in
            partial + Int64(output.data.count)
        }
        let mediaReferenceCount = snapshot.payload.evidenceCards.reduce(0) {
            $0 + $1.outputReferences.count
        }
        guard renderedBytes <= exportProfile.maximumArchiveBytes,
              mediaReferenceCount <= exportProfile.maximumMediaItems else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }

        let reopenedJSON = try DeterministicOpenJSONRendererV1.reopen(openJSON.data)
        let reopenedText = try DeterministicOpenJSONRendererV1.reopenStructuredText(text.data)
        let reopenedPDF = try DeterministicPDFRendererV1.reopen(pdf.data)
        guard reopenedJSON == semantic,
              reopenedText == semantic,
              reopenedPDF == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return .complete(try ReportProjectionBundleV1(
            snapshot: snapshot,
            semanticProjection: semantic,
            pdf: pdf,
            openJSON: openJSON,
            structuredText: text
        ))
    }

    func recover(
        snapshot: CompletedActivitySnapshotV1,
        manifest: ContractManifestV1,
        reportProfile: ReportLayoutProfileV1,
        exportProfile: ExportProfileV1,
        storedBundle: ReportProjectionBundleV1?
    ) throws -> ReportProjectionBundleV1 {
        guard case .complete(let regenerated) = try render(
            snapshot: snapshot,
            manifest: manifest,
            reportProfile: reportProfile,
            exportProfile: exportProfile
        ) else {
            throw SnapshotProjectionFailureV1.partialEffect
        }
        if let storedBundle, storedBundle != regenerated {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return regenerated
    }

    func render(
        snapshot: CompletedActivitySnapshotV2,
        manifest: ContractManifestV1,
        reportProfile: ReportLayoutProfileV1,
        exportProfile: ExportProfileV1,
        recoveringFrom boundary: ReportProjectionPublicationBoundaryV1? = nil
    ) throws -> ReportProjectionPublicationV1 {
        if boundary == .beforeValidation { return .zero }
        try validate(); try snapshot.validate(); try manifest.validate()
        try reportProfile.validate(against: manifest.reportSectionRegistry)
        try exportProfile.validate()
        _ = try CompletedActivitySnapshotCanonicalCodecV2.encode(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let sectionRegistrySHA256 = KernelCanonicalHashV1.sha256(
            try encoder.encode(manifest.reportSectionRegistry)
        )
        let manifestSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(manifest))
        let reportProfileSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(reportProfile))
        let exportProfileSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(exportProfile))
        let activity = snapshot.payload.activity
        let binding = activity.profileBinding
        try binding.validate()
        guard sectionRegistrySHA256 == binding.sectionRegistrySHA256,
              manifest.reportSectionRegistry.registryID == binding.sectionRegistryID,
              manifest.reportSectionRegistry.registryVersion == binding.sectionRegistryVersion,
              manifest.manifestID == binding.contractManifestID,
              manifest.manifestVersion == binding.contractManifestVersion,
              manifestSHA256 == binding.contractManifestSHA256,
              reportProfileSHA256 == binding.reportProfileSHA256,
              reportProfile.profileID == binding.reportProfileID,
              reportProfile.profileRelease == binding.reportProfileRelease,
              reportProfile.sectionIDs == binding.sectionIDs,
              reportProfile.audience == binding.audience,
              reportProfile.detail == binding.detail,
              reportProfile.localeIdentifier == binding.localeIdentifier,
              reportProfile.unitsProfileID == binding.unitsProfileID,
              reportProfile.displayProfileID == binding.displayProfileID,
              reportProfile.orientation == binding.orientation,
              reportProfile.mediaLayout == binding.mediaLayout,
              exportProfileSHA256 == binding.exportProfileSHA256,
              exportProfile.exportProfileID == binding.exportProfileID,
              exportProfile.exportProfileRelease == binding.exportProfileRelease,
              exportProfile.privacyTransformID == binding.privacyTransformID,
              Set(requiredFormats).isSubset(of: Set(exportProfile.formats)),
              manifest.reportSectionRegistry.requiredSectionIDs.isSubset(of: Set(binding.sectionIDs)),
              binding.sectionIDs.allSatisfy({ id in
                  manifest.reportSectionRegistry.sections.contains(where: { $0.sectionID == id })
              }),
              binding.sectionIDs.allSatisfy({ id in
                  guard let section = manifest.reportSectionRegistry.sections.first(where: { $0.sectionID == id }) else {
                      return false
                  }
                  return Set(requiredFormats).isSubset(of: Set(section.supportedFormats))
              }),
              binding.rendererVersion == soleRenderer,
              activity.evidenceCards.allSatisfy({ $0.audience == binding.audience }) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        if boundary == .afterValidation { return .zero }
        let semantic = try ReportSemanticProjectorV1.project(snapshot: snapshot, manifest: manifest)
        if boundary == .afterSemanticProjection { return .zero }
        let openJSON = try DeterministicOpenJSONRendererV1.render(semantic)
        if boundary == .afterOpenJSON { return .zero }
        let pdf = try DeterministicPDFRendererV1.render(semantic, layoutProfile: reportProfile)
        if boundary == .afterPDF { return .zero }
        let text = try DeterministicOpenJSONRendererV1.renderStructuredText(semantic)
        if boundary == .afterStructuredText || boundary == .afterReopenValidationBeforePublication {
            return .zero
        }
        let renderedBytes = [openJSON, pdf, text].reduce(Int64(0)) {
            $0 + Int64($1.data.count)
        }
        let mediaReferenceCount = activity.evidenceCards.reduce(0) {
            $0 + $1.outputReferences.count
        }
        guard renderedBytes <= exportProfile.maximumArchiveBytes,
              mediaReferenceCount <= exportProfile.maximumMediaItems else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        guard try DeterministicOpenJSONRendererV1.reopen(openJSON.data) == semantic,
              try DeterministicOpenJSONRendererV1.reopenStructuredText(text.data) == semantic,
              try DeterministicPDFRendererV1.reopen(pdf.data) == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return .complete(try ReportProjectionBundleV1(
            snapshot: snapshot,
            semanticProjection: semantic,
            pdf: pdf,
            openJSON: openJSON,
            structuredText: text
        ))
    }

    func recover(
        snapshot: CompletedActivitySnapshotV2,
        manifest: ContractManifestV1,
        reportProfile: ReportLayoutProfileV1,
        exportProfile: ExportProfileV1,
        storedBundle: ReportProjectionBundleV1?
    ) throws -> ReportProjectionBundleV1 {
        guard case .complete(let regenerated) = try render(
            snapshot: snapshot, manifest: manifest,
            reportProfile: reportProfile, exportProfile: exportProfile
        ) else { throw SnapshotProjectionFailureV1.partialEffect }
        if let storedBundle, storedBundle != regenerated {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return regenerated
    }
}

/// Additive registry release for completed-activity snapshot V2. The frozen
/// V1 registry remains unchanged for historic snapshots and encoded fixtures.
struct ReportProjectionRegistryV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2
    static let registryID = "report-projection-registry-v2"
    let schemaVersion: Int
    let registryID: String
    let supportedPersistentContractSchemas: [String]
    let baseRendererRegistry: ReportProjectionRegistryV1

    init() {
        schemaVersion = Self.schemaVersion
        registryID = Self.registryID
        supportedPersistentContractSchemas = ["KERNEL_SNAPSHOT_V1", "KERNEL_SNAPSHOT_V2"]
        baseRendererRegistry = ReportProjectionRegistryV1()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, registryID, supportedPersistentContractSchemas
        case baseRendererRegistry
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let expected = Self()
        guard try values.decode(Int.self, forKey: .schemaVersion) == expected.schemaVersion,
              try values.decode(String.self, forKey: .registryID) == expected.registryID,
              try values.decode([String].self, forKey: .supportedPersistentContractSchemas)
                == expected.supportedPersistentContractSchemas,
              try values.decode(ReportProjectionRegistryV1.self, forKey: .baseRendererRegistry)
                == expected.baseRendererRegistry else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        self = expected
    }

    func validate() throws {
        guard self == Self() else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        try baseRendererRegistry.validate()
        guard ReportAccountabilityProjectionPolicyV1.sectionID == "accountability",
              ReportAccountabilityProjectionPolicyV1.sectionVersion == 1,
              ReportAccountabilityProjectionPolicyV1.supports(.openJSON),
              ReportAccountabilityProjectionPolicyV1.supports(.structuredText) else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
    }

    func render(
        snapshot: CompletedActivitySnapshotV2,
        manifest: ContractManifestV1,
        reportProfile: ReportLayoutProfileV1,
        exportProfile: ExportProfileV1,
        recoveringFrom boundary: ReportProjectionPublicationBoundaryV1? = nil
    ) throws -> ReportProjectionPublicationV1 {
        try validate()
        return try baseRendererRegistry.render(
            snapshot: snapshot, manifest: manifest,
            reportProfile: reportProfile, exportProfile: exportProfile,
            recoveringFrom: boundary
        )
    }

    func recover(
        snapshot: CompletedActivitySnapshotV2,
        manifest: ContractManifestV1,
        reportProfile: ReportLayoutProfileV1,
        exportProfile: ExportProfileV1,
        storedBundle: ReportProjectionBundleV1?
    ) throws -> ReportProjectionBundleV1 {
        try validate()
        return try baseRendererRegistry.recover(
            snapshot: snapshot, manifest: manifest,
            reportProfile: reportProfile, exportProfile: exportProfile,
            storedBundle: storedBundle
        )
    }
}

/// Additive registry release for C38's completed-activity accountability
/// projection. Historic V1/V2 registries remain valid and continue to render
/// their original byte shape.
struct ReportProjectionRegistryV3: Codable, Equatable, Sendable {
    static let schemaVersion = 3
    static let registryID = "report-projection-registry-v3"
    let schemaVersion: Int
    let registryID: String
    let supportedPersistentContractSchemas: [String]
    let baseRendererRegistry: ReportProjectionRegistryV1

    init() {
        schemaVersion = Self.schemaVersion
        registryID = Self.registryID
        supportedPersistentContractSchemas = [
            "KERNEL_SNAPSHOT_V1", "KERNEL_SNAPSHOT_V2", "KERNEL_SNAPSHOT_V3",
        ]
        baseRendererRegistry = ReportProjectionRegistryV1()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, registryID, supportedPersistentContractSchemas
        case baseRendererRegistry
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let expected = Self()
        guard try values.decode(Int.self, forKey: .schemaVersion) == expected.schemaVersion,
              try values.decode(String.self, forKey: .registryID) == expected.registryID,
              try values.decode([String].self, forKey: .supportedPersistentContractSchemas)
                    == expected.supportedPersistentContractSchemas,
              try values.decode(ReportProjectionRegistryV1.self, forKey: .baseRendererRegistry)
                    == expected.baseRendererRegistry else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        self = expected
    }

    func validate() throws {
        guard self == Self() else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        try baseRendererRegistry.validate()
    }

    func render(
        snapshot: CompletedActivitySnapshotV3,
        manifest: ContractManifestV1,
        reportProfile: ReportLayoutProfileV1,
        exportProfile: ExportProfileV1,
        recoveringFrom boundary: ReportProjectionPublicationBoundaryV1? = nil
    ) throws -> ReportProjectionPublicationV1 {
        if boundary == .beforeValidation { return .zero }
        try validate()
        try snapshot.validate()
        try manifest.validate()
        try reportProfile.validate(against: manifest.reportSectionRegistry)
        try exportProfile.validate()
        _ = try CompletedActivitySnapshotCanonicalCodecV3.encode(snapshot)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let sectionRegistrySHA256 = KernelCanonicalHashV1.sha256(
            try encoder.encode(manifest.reportSectionRegistry)
        )
        let manifestSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(manifest))
        let reportProfileSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(reportProfile))
        let exportProfileSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(exportProfile))
        let activity = snapshot.payload.activity.activity
        let binding = activity.profileBinding
        try binding.validate()
        if snapshot.payload.accountability != nil {
            guard binding.sectionIDs.contains(ReportAccountabilityProjectionPolicyV1.sectionID) else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
        guard sectionRegistrySHA256 == binding.sectionRegistrySHA256,
              manifest.reportSectionRegistry.registryID == binding.sectionRegistryID,
              manifest.reportSectionRegistry.registryVersion == binding.sectionRegistryVersion,
              manifest.manifestID == binding.contractManifestID,
              manifest.manifestVersion == binding.contractManifestVersion,
              manifestSHA256 == binding.contractManifestSHA256,
              reportProfileSHA256 == binding.reportProfileSHA256,
              reportProfile.profileID == binding.reportProfileID,
              reportProfile.profileRelease == binding.reportProfileRelease,
              reportProfile.sectionIDs == binding.sectionIDs,
              reportProfile.audience == binding.audience,
              reportProfile.detail == binding.detail,
              reportProfile.localeIdentifier == binding.localeIdentifier,
              reportProfile.unitsProfileID == binding.unitsProfileID,
              reportProfile.displayProfileID == binding.displayProfileID,
              reportProfile.orientation == binding.orientation,
              reportProfile.mediaLayout == binding.mediaLayout,
              exportProfileSHA256 == binding.exportProfileSHA256,
              exportProfile.exportProfileID == binding.exportProfileID,
              exportProfile.exportProfileRelease == binding.exportProfileRelease,
              exportProfile.privacyTransformID == binding.privacyTransformID,
              Set(requiredFormats).isSubset(of: Set(exportProfile.formats)),
              manifest.reportSectionRegistry.requiredSectionIDs.isSubset(of: Set(binding.sectionIDs)),
              binding.sectionIDs.allSatisfy({ id in
                  manifest.reportSectionRegistry.sections.contains(where: { $0.sectionID == id })
              }),
              binding.sectionIDs.allSatisfy({ id in
                  guard let section = manifest.reportSectionRegistry.sections.first(where: { $0.sectionID == id }) else {
                      return false
                  }
                  return Set(requiredFormats).isSubset(of: Set(section.supportedFormats))
              }),
              binding.rendererVersion == baseRendererRegistry.soleRenderer,
              activity.evidenceCards.allSatisfy({ $0.audience == binding.audience }) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        if boundary == .afterValidation { return .zero }

        let semantic = try ReportSemanticProjectorV1.project(snapshot: snapshot, manifest: manifest)
        if boundary == .afterSemanticProjection { return .zero }
        let openJSON = try DeterministicOpenJSONRendererV1.render(semantic)
        if boundary == .afterOpenJSON { return .zero }
        let pdf = try DeterministicPDFRendererV1.render(semantic, layoutProfile: reportProfile)
        if boundary == .afterPDF { return .zero }
        let text = try DeterministicOpenJSONRendererV1.renderStructuredText(semantic)
        if boundary == .afterStructuredText || boundary == .afterReopenValidationBeforePublication {
            return .zero
        }

        let renderedBytes = [openJSON, pdf, text].reduce(Int64(0)) {
            $0 + Int64($1.data.count)
        }
        let mediaReferenceCount = activity.evidenceCards.reduce(0) {
            $0 + $1.outputReferences.count
        }
        guard renderedBytes <= exportProfile.maximumArchiveBytes,
              mediaReferenceCount <= exportProfile.maximumMediaItems else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        guard try DeterministicOpenJSONRendererV1.reopen(openJSON.data) == semantic,
              try DeterministicOpenJSONRendererV1.reopenStructuredText(text.data) == semantic,
              try DeterministicPDFRendererV1.reopen(pdf.data) == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return .complete(try ReportProjectionBundleV1(
            snapshot: snapshot,
            semanticProjection: semantic,
            pdf: pdf,
            openJSON: openJSON,
            structuredText: text
        ))
    }

    func recover(
        snapshot: CompletedActivitySnapshotV3,
        manifest: ContractManifestV1,
        reportProfile: ReportLayoutProfileV1,
        exportProfile: ExportProfileV1,
        storedBundle: ReportProjectionBundleV1?
    ) throws -> ReportProjectionBundleV1 {
        try validate()
        guard case .complete(let regenerated) = try render(
            snapshot: snapshot,
            manifest: manifest,
            reportProfile: reportProfile,
            exportProfile: exportProfile
        ) else {
            throw SnapshotProjectionFailureV1.partialEffect
        }
        if let storedBundle, storedBundle != regenerated {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return regenerated
    }

    private var requiredFormats: [ReportProjectionFormatV1] {
        baseRendererRegistry.requiredFormats
    }
}

/// Additive C39 registry. Existing V1/V2/V3 report registries and their
/// encoded output remain untouched; V4 is selected only for snapshots carrying
/// the immutable asset-semantic projection.
struct ReportProjectionRegistryV4: Codable, Equatable, Sendable {
    static let schemaVersion = 4
    static let registryID = "report-projection-registry-v4"
    static let persistentContractSchema = "KERNEL_SNAPSHOT_V4"
    let schemaVersion: Int
    let registryID: String
    let supportedPersistentContractSchemas: [String]
    let baseRendererRegistry: ReportProjectionRegistryV1

    init() {
        schemaVersion = Self.schemaVersion
        registryID = Self.registryID
        supportedPersistentContractSchemas = [
            "KERNEL_SNAPSHOT_V1", "KERNEL_SNAPSHOT_V2", "KERNEL_SNAPSHOT_V3", "KERNEL_SNAPSHOT_V4",
        ]
        baseRendererRegistry = ReportProjectionRegistryV1()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, registryID, supportedPersistentContractSchemas, baseRendererRegistry
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let expected = Self()
        guard try values.decode(Int.self, forKey: .schemaVersion) == expected.schemaVersion,
              try values.decode(String.self, forKey: .registryID) == expected.registryID,
              try values.decode([String].self, forKey: .supportedPersistentContractSchemas)
                    == expected.supportedPersistentContractSchemas,
              try values.decode(ReportProjectionRegistryV1.self, forKey: .baseRendererRegistry)
                    == expected.baseRendererRegistry else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        self = expected
    }

    func validate() throws {
        guard self == Self() else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        try baseRendererRegistry.validate()
        guard ReportAssetSemanticsProjectionPolicyV1.sectionID == "asset-semantics",
              ReportAssetSemanticsProjectionPolicyV1.sectionVersion == 1,
              ReportAssetSemanticsProjectionPolicyV1.supports(.openJSON),
              ReportAssetSemanticsProjectionPolicyV1.supports(.structuredText),
              ReportAssetSemanticsProjectionPolicyV1.excludesOperationalDisposition,
              ReportAssetSemanticsProjectionPolicyV1.excludesProductIdentifierValues else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
    }

    func render(
        snapshot: CompletedActivitySnapshotV4,
        manifest: ContractManifestV1,
        reportProfile: ReportLayoutProfileV1,
        exportProfile: ExportProfileV1,
        recoveringFrom boundary: ReportProjectionPublicationBoundaryV1? = nil
    ) throws -> ReportProjectionPublicationV1 {
        if boundary == .beforeValidation { return .zero }
        try validate()
        try snapshot.validate()
        try manifest.validate()
        try reportProfile.validate(against: manifest.reportSectionRegistry)
        try exportProfile.validate()
        _ = try CompletedActivitySnapshotCanonicalCodecV4.encode(snapshot)

        let binding = snapshot.payload.activity.activity.activity.profileBinding
        try binding.validate()
        if snapshot.payload.activity.accountability != nil {
            guard binding.sectionIDs.contains(ReportAccountabilityProjectionPolicyV1.sectionID) else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
        if snapshot.payload.assetSemantics != nil {
            guard binding.sectionIDs.contains(ReportAssetSemanticsProjectionPolicyV1.sectionID) else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let sectionRegistrySHA256 = KernelCanonicalHashV1.sha256(
            try encoder.encode(manifest.reportSectionRegistry)
        )
        let manifestSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(manifest))
        let reportProfileSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(reportProfile))
        let exportProfileSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(exportProfile))
        let activity = snapshot.payload.activity.activity.activity
        guard sectionRegistrySHA256 == binding.sectionRegistrySHA256,
              manifest.reportSectionRegistry.registryID == binding.sectionRegistryID,
              manifest.reportSectionRegistry.registryVersion == binding.sectionRegistryVersion,
              manifest.manifestID == binding.contractManifestID,
              manifest.manifestVersion == binding.contractManifestVersion,
              manifestSHA256 == binding.contractManifestSHA256,
              reportProfileSHA256 == binding.reportProfileSHA256,
              reportProfile.profileID == binding.reportProfileID,
              reportProfile.profileRelease == binding.reportProfileRelease,
              reportProfile.sectionIDs == binding.sectionIDs,
              reportProfile.audience == binding.audience,
              reportProfile.detail == binding.detail,
              reportProfile.localeIdentifier == binding.localeIdentifier,
              reportProfile.unitsProfileID == binding.unitsProfileID,
              reportProfile.displayProfileID == binding.displayProfileID,
              reportProfile.orientation == binding.orientation,
              reportProfile.mediaLayout == binding.mediaLayout,
              exportProfileSHA256 == binding.exportProfileSHA256,
              exportProfile.exportProfileID == binding.exportProfileID,
              exportProfile.exportProfileRelease == binding.exportProfileRelease,
              exportProfile.privacyTransformID == binding.privacyTransformID,
              Set(requiredFormats).isSubset(of: Set(exportProfile.formats)),
              manifest.reportSectionRegistry.requiredSectionIDs.isSubset(of: Set(binding.sectionIDs)),
              binding.sectionIDs.allSatisfy({ id in
                  manifest.reportSectionRegistry.sections.contains(where: { $0.sectionID == id })
              }),
              binding.sectionIDs.allSatisfy({ id in
                  guard let section = manifest.reportSectionRegistry.sections.first(where: { $0.sectionID == id }) else {
                      return false
                  }
                  return Set(requiredFormats).isSubset(of: Set(section.supportedFormats))
              }),
              binding.rendererVersion == baseRendererRegistry.soleRenderer,
              activity.evidenceCards.allSatisfy({ $0.audience == binding.audience }) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        if boundary == .afterValidation { return .zero }
        let semantic = try ReportSemanticProjectorV1.project(snapshot: snapshot, manifest: manifest)
        if boundary == .afterSemanticProjection { return .zero }
        let openJSON = try DeterministicOpenJSONRendererV1.render(semantic)
        if boundary == .afterOpenJSON { return .zero }
        let pdf = try DeterministicPDFRendererV1.render(semantic, layoutProfile: reportProfile)
        if boundary == .afterPDF { return .zero }
        let text = try DeterministicOpenJSONRendererV1.renderStructuredText(semantic)
        if boundary == .afterStructuredText || boundary == .afterReopenValidationBeforePublication {
            return .zero
        }
        let renderedBytes = [openJSON, pdf, text].reduce(Int64(0)) { $0 + Int64($1.data.count) }
        let mediaReferenceCount = activity.evidenceCards.reduce(0) { $0 + $1.outputReferences.count }
        guard renderedBytes <= exportProfile.maximumArchiveBytes,
              mediaReferenceCount <= exportProfile.maximumMediaItems,
              try DeterministicOpenJSONRendererV1.reopen(openJSON.data) == semantic,
              try DeterministicOpenJSONRendererV1.reopenStructuredText(text.data) == semantic,
              try DeterministicPDFRendererV1.reopen(pdf.data) == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return .complete(try ReportProjectionBundleV1(
            snapshot: snapshot,
            semanticProjection: semantic,
            pdf: pdf,
            openJSON: openJSON,
            structuredText: text
        ))
    }

    func recover(
        snapshot: CompletedActivitySnapshotV4,
        manifest: ContractManifestV1,
        reportProfile: ReportLayoutProfileV1,
        exportProfile: ExportProfileV1,
        storedBundle: ReportProjectionBundleV1?
    ) throws -> ReportProjectionBundleV1 {
        try validate()
        guard case .complete(let regenerated) = try render(
            snapshot: snapshot,
            manifest: manifest,
            reportProfile: reportProfile,
            exportProfile: exportProfile
        ) else { throw SnapshotProjectionFailureV1.partialEffect }
        if let storedBundle, storedBundle != regenerated {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return regenerated
    }

    private var requiredFormats: [ReportProjectionFormatV1] {
        baseRendererRegistry.requiredFormats
    }
}

/// Additive C40 registry identity. V5 selects the same deterministic renderer
/// family while requiring the authority/criterion section whenever a frozen
/// C40 projection is present.
struct ReportProjectionRegistryV5: Codable, Equatable, Sendable {
    static let schemaVersion = 5
    static let registryID = "report-projection-registry-v5"
    static let persistentContractSchema = "KERNEL_SNAPSHOT_V5"
    let schemaVersion: Int
    let registryID: String
    let supportedPersistentContractSchemas: [String]
    let baseRendererRegistry: ReportProjectionRegistryV1

    init() {
        schemaVersion = Self.schemaVersion
        registryID = Self.registryID
        supportedPersistentContractSchemas = [
            "KERNEL_SNAPSHOT_V1", "KERNEL_SNAPSHOT_V2", "KERNEL_SNAPSHOT_V3",
            "KERNEL_SNAPSHOT_V4", "KERNEL_SNAPSHOT_V5",
        ]
        baseRendererRegistry = ReportProjectionRegistryV1()
    }

    func validate() throws {
        guard self == Self(),
              ReportAuthorityCriterionProjectionPolicyV1.sectionID == "authority-criterion",
              ReportAuthorityCriterionProjectionPolicyV1.requiredWording == "assessed against",
              ReportAuthorityCriterionProjectionPolicyV1.supports(.openJSON),
              ReportAuthorityCriterionProjectionPolicyV1.supports(.structuredText),
              ReportAuthorityCriterionProjectionPolicyV1.excludesLicensedSourceBytes,
              ReportAuthorityCriterionProjectionPolicyV1.excludesRawLocators,
              ReportAuthorityCriterionProjectionPolicyV1.excludesLegalSafetyComplianceClaims else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try baseRendererRegistry.validate()
    }

    func semanticProjection(
        snapshot: CompletedActivitySnapshotV5,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        try validate(); try snapshot.validate(); try manifest.validate()
        if snapshot.payload.authorityCriterion != nil {
            let binding = snapshot.payload.activity.activity.activity.activity.profileBinding
            guard binding.sectionIDs.contains(ReportAuthorityCriterionProjectionPolicyV1.sectionID) else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
        return try ReportSemanticProjectorV1.project(snapshot: snapshot, manifest: manifest)
    }

    func renderOpenJSON(
        snapshot: CompletedActivitySnapshotV5,
        manifest: ContractManifestV1
    ) throws -> ReportProjectionOutputV1 {
        let semantic = try semanticProjection(snapshot: snapshot, manifest: manifest)
        let output = try DeterministicOpenJSONRendererV1.render(semantic)
        guard try DeterministicOpenJSONRendererV1.reopen(output.data) == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return output
    }

    func renderStructuredText(
        snapshot: CompletedActivitySnapshotV5,
        manifest: ContractManifestV1
    ) throws -> ReportProjectionOutputV1 {
        let semantic = try semanticProjection(snapshot: snapshot, manifest: manifest)
        let output = try DeterministicOpenJSONRendererV1.renderStructuredText(semantic)
        guard try DeterministicOpenJSONRendererV1.reopenStructuredText(output.data) == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return output
    }
}

/// Additive C41 registry. It binds the V6 completed-work snapshot to the
/// frozen functional-relationship descriptor/history section while retaining
/// the deterministic report renderer family.
struct ReportProjectionRegistryV6: Codable, Equatable, Sendable {
    static let schemaVersion = 6
    static let registryID = "report-projection-registry-v6"
    static let persistentContractSchema = "KERNEL_SNAPSHOT_V6"
    let schemaVersion: Int
    let registryID: String
    let supportedPersistentContractSchemas: [String]
    let baseRendererRegistry: ReportProjectionRegistryV1

    init() {
        schemaVersion = Self.schemaVersion
        registryID = Self.registryID
        supportedPersistentContractSchemas = [
            "KERNEL_SNAPSHOT_V1", "KERNEL_SNAPSHOT_V2", "KERNEL_SNAPSHOT_V3",
            "KERNEL_SNAPSHOT_V4", "KERNEL_SNAPSHOT_V5", "KERNEL_SNAPSHOT_V6",
        ]
        baseRendererRegistry = ReportProjectionRegistryV1()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, registryID, supportedPersistentContractSchemas, baseRendererRegistry
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let expected = Self()
        guard try values.decode(Int.self, forKey: .schemaVersion) == expected.schemaVersion,
              try values.decode(String.self, forKey: .registryID) == expected.registryID,
              try values.decode([String].self, forKey: .supportedPersistentContractSchemas)
                    == expected.supportedPersistentContractSchemas,
              try values.decode(ReportProjectionRegistryV1.self, forKey: .baseRendererRegistry)
                    == expected.baseRendererRegistry else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        self = expected
    }

    func validate() throws {
        guard self == Self(),
              ReportFunctionalRelationshipsProjectionPolicyV1.sectionID == "functional-relationships",
              ReportFunctionalRelationshipsProjectionPolicyV1.sectionVersion == 1,
              ReportFunctionalRelationshipsProjectionPolicyV1.projectionVersion
                    == "report-functional-relationships-v1",
              ReportFunctionalRelationshipsProjectionPolicyV1.requiredTypedLabels,
              ReportFunctionalRelationshipsProjectionPolicyV1.excludesOwnershipAuthorizationComplianceClaims,
              ReportFunctionalRelationshipsProjectionPolicyV1.excludesTelemetryAndOperationalClaims,
              ReportFunctionalRelationshipsProjectionPolicyV1.excludesRawLocators,
              ReportFunctionalRelationshipsProjectionPolicyV1.supports(.openJSON),
              ReportFunctionalRelationshipsProjectionPolicyV1.supports(.structuredText) else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try baseRendererRegistry.validate()
    }

    func semanticProjection(
        snapshot: CompletedActivitySnapshotV6,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        try validate()
        try snapshot.validate()
        try manifest.validate()
        let binding = snapshot.payload.activity.activity.activity.activity.activity.profileBinding
        guard binding.sectionIDs.contains(ReportFunctionalRelationshipsProjectionPolicyV1.sectionID) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        return try ReportSemanticProjectorV1.project(snapshot: snapshot, manifest: manifest)
    }

    func renderOpenJSON(
        snapshot: CompletedActivitySnapshotV6,
        manifest: ContractManifestV1
    ) throws -> ReportProjectionOutputV1 {
        let semantic = try semanticProjection(snapshot: snapshot, manifest: manifest)
        let output = try DeterministicOpenJSONRendererV1.render(semantic)
        guard try DeterministicOpenJSONRendererV1.reopen(output.data) == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return output
    }

    func renderStructuredText(
        snapshot: CompletedActivitySnapshotV6,
        manifest: ContractManifestV1
    ) throws -> ReportProjectionOutputV1 {
        let semantic = try semanticProjection(snapshot: snapshot, manifest: manifest)
        let output = try DeterministicOpenJSONRendererV1.renderStructuredText(semantic)
        guard try DeterministicOpenJSONRendererV1.reopenStructuredText(output.data) == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return output
    }

    func render(
        snapshot: CompletedActivitySnapshotV6,
        manifest: ContractManifestV1,
        reportProfile: ReportLayoutProfileV1,
        exportProfile: ExportProfileV1,
        recoveringFrom boundary: ReportProjectionPublicationBoundaryV1? = nil
    ) throws -> ReportProjectionPublicationV1 {
        if boundary == .beforeValidation { return .zero }
        try validate()
        try snapshot.validate()
        try manifest.validate()
        try reportProfile.validate(against: manifest.reportSectionRegistry)
        try exportProfile.validate()
        _ = try CompletedActivitySnapshotCanonicalCodecV6.encode(snapshot)
        let binding = snapshot.payload.activity.activity.activity.activity.activity.profileBinding
        try binding.validate()
        guard binding.sectionIDs.contains(ReportFunctionalRelationshipsProjectionPolicyV1.sectionID) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let sectionRegistrySHA256 = KernelCanonicalHashV1.sha256(
            try encoder.encode(manifest.reportSectionRegistry)
        )
        let manifestSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(manifest))
        let reportProfileSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(reportProfile))
        let exportProfileSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(exportProfile))
        let activity = snapshot.payload.activity.activity.activity.activity.activity
        guard sectionRegistrySHA256 == binding.sectionRegistrySHA256,
              manifest.reportSectionRegistry.registryID == binding.sectionRegistryID,
              manifest.reportSectionRegistry.registryVersion == binding.sectionRegistryVersion,
              manifest.manifestID == binding.contractManifestID,
              manifest.manifestVersion == binding.contractManifestVersion,
              manifestSHA256 == binding.contractManifestSHA256,
              reportProfileSHA256 == binding.reportProfileSHA256,
              reportProfile.profileID == binding.reportProfileID,
              reportProfile.profileRelease == binding.reportProfileRelease,
              reportProfile.sectionIDs == binding.sectionIDs,
              reportProfile.audience == binding.audience,
              reportProfile.detail == binding.detail,
              reportProfile.localeIdentifier == binding.localeIdentifier,
              reportProfile.unitsProfileID == binding.unitsProfileID,
              reportProfile.displayProfileID == binding.displayProfileID,
              reportProfile.orientation == binding.orientation,
              reportProfile.mediaLayout == binding.mediaLayout,
              exportProfileSHA256 == binding.exportProfileSHA256,
              exportProfile.exportProfileID == binding.exportProfileID,
              exportProfile.exportProfileRelease == binding.exportProfileRelease,
              exportProfile.privacyTransformID == binding.privacyTransformID,
              Set([ReportProjectionFormatV1.openJSON, .pdf, .structuredText])
                    .isSubset(of: Set(exportProfile.formats)),
              manifest.reportSectionRegistry.requiredSectionIDs.isSubset(of: Set(binding.sectionIDs)),
              binding.sectionIDs.allSatisfy({ id in
                  manifest.reportSectionRegistry.sections.contains(where: { $0.sectionID == id })
              }),
              binding.sectionIDs.allSatisfy({ id in
                  guard let section = manifest.reportSectionRegistry.sections.first(where: { $0.sectionID == id }) else {
                      return false
                  }
                  return Set([ReportProjectionFormatV1.openJSON, .pdf, .structuredText])
                        .isSubset(of: Set(section.supportedFormats))
              }),
              binding.rendererVersion == baseRendererRegistry.soleRenderer,
              activity.evidenceCards.allSatisfy({ $0.audience == binding.audience }) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        if boundary == .afterValidation { return .zero }
        let semantic = try ReportSemanticProjectorV1.project(snapshot: snapshot, manifest: manifest)
        if boundary == .afterSemanticProjection { return .zero }
        let openJSON = try DeterministicOpenJSONRendererV1.render(semantic)
        if boundary == .afterOpenJSON { return .zero }
        let pdf = try DeterministicPDFRendererV1.render(semantic, layoutProfile: reportProfile)
        if boundary == .afterPDF { return .zero }
        let text = try DeterministicOpenJSONRendererV1.renderStructuredText(semantic)
        if boundary == .afterStructuredText || boundary == .afterReopenValidationBeforePublication {
            return .zero
        }
        let renderedBytes = [openJSON, pdf, text].reduce(Int64(0)) { $0 + Int64($1.data.count) }
        let mediaReferenceCount = activity.evidenceCards.reduce(0) { $0 + $1.outputReferences.count }
        guard renderedBytes <= exportProfile.maximumArchiveBytes,
              mediaReferenceCount <= exportProfile.maximumMediaItems,
              try DeterministicOpenJSONRendererV1.reopen(openJSON.data) == semantic,
              try DeterministicOpenJSONRendererV1.reopenStructuredText(text.data) == semantic,
              try DeterministicPDFRendererV1.reopen(pdf.data) == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return .complete(try ReportProjectionBundleV1(
            snapshot: snapshot,
            semanticProjection: semantic,
            pdf: pdf,
            openJSON: openJSON,
            structuredText: text
        ))
    }

    func recover(
        snapshot: CompletedActivitySnapshotV6,
        manifest: ContractManifestV1,
        reportProfile: ReportLayoutProfileV1,
        exportProfile: ExportProfileV1,
        storedBundle: ReportProjectionBundleV1?
    ) throws -> ReportProjectionBundleV1 {
        try validate()
        guard case .complete(let regenerated) = try render(
            snapshot: snapshot,
            manifest: manifest,
            reportProfile: reportProfile,
            exportProfile: exportProfile
        ) else {
            throw SnapshotProjectionFailureV1.partialEffect
        }
        if let storedBundle, storedBundle != regenerated {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return regenerated
    }
}

/// Additive C13 registry. It admits only the completed V7 assurance wrapper
/// and exposes preview/open-JSON/structured-text projection helpers. There is
/// deliberately no finalization, recovery producer, hosted, adoption,
/// acceptance, or release path in this registry.
struct ReportProjectionRegistryV7: Codable, Equatable, Sendable {
    static let schemaVersion = 7
    static let registryID = "report-projection-registry-v7"
    static let persistentContractSchema = "KERNEL_SNAPSHOT_V7"
    static let publicationDisposition = ReportEvidenceAssuranceProjectionPolicyV1.publicationDisposition
    static let nativeCompileRan = false
    static let hostedDispatchRan = false
    static let adoptionEnabled = false
    static let acceptanceCredit = false
    static let releaseCredit = false

    let schemaVersion: Int
    let registryID: String
    let persistentContractSchema: String
    let supportedPersistentContractSchemas: [String]
    let publicationDisposition: String
    let nativeCompileRan: Bool
    let hostedDispatchRan: Bool
    let adoptionEnabled: Bool
    let acceptanceCredit: Bool
    let releaseCredit: Bool
    let baseRendererRegistry: ReportProjectionRegistryV1

    init() {
        schemaVersion = Self.schemaVersion
        registryID = Self.registryID
        persistentContractSchema = Self.persistentContractSchema
        supportedPersistentContractSchemas = [
            "KERNEL_SNAPSHOT_V1", "KERNEL_SNAPSHOT_V2", "KERNEL_SNAPSHOT_V3",
            "KERNEL_SNAPSHOT_V4", "KERNEL_SNAPSHOT_V5", "KERNEL_SNAPSHOT_V6",
            "KERNEL_SNAPSHOT_V7",
        ]
        publicationDisposition = Self.publicationDisposition
        nativeCompileRan = Self.nativeCompileRan
        hostedDispatchRan = Self.hostedDispatchRan
        adoptionEnabled = Self.adoptionEnabled
        acceptanceCredit = Self.acceptanceCredit
        releaseCredit = Self.releaseCredit
        baseRendererRegistry = ReportProjectionRegistryV1()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, registryID, persistentContractSchema
        case supportedPersistentContractSchemas, publicationDisposition
        case nativeCompileRan, hostedDispatchRan, adoptionEnabled
        case acceptanceCredit, releaseCredit, baseRendererRegistry
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let expected = Self()
        guard try values.decode(Int.self, forKey: .schemaVersion) == expected.schemaVersion,
              try values.decode(String.self, forKey: .registryID) == expected.registryID,
              try values.decode(String.self, forKey: .persistentContractSchema)
                    == expected.persistentContractSchema,
              try values.decode([String].self, forKey: .supportedPersistentContractSchemas)
                    == expected.supportedPersistentContractSchemas,
              try values.decode(String.self, forKey: .publicationDisposition)
                    == expected.publicationDisposition,
              try values.decode(Bool.self, forKey: .nativeCompileRan) == expected.nativeCompileRan,
              try values.decode(Bool.self, forKey: .hostedDispatchRan) == expected.hostedDispatchRan,
              try values.decode(Bool.self, forKey: .adoptionEnabled) == expected.adoptionEnabled,
              try values.decode(Bool.self, forKey: .acceptanceCredit) == expected.acceptanceCredit,
              try values.decode(Bool.self, forKey: .releaseCredit) == expected.releaseCredit,
              try values.decode(ReportProjectionRegistryV1.self, forKey: .baseRendererRegistry)
                    == expected.baseRendererRegistry else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        self = expected
    }

    func validate() throws {
        guard self == Self(),
              ReportEvidenceAssuranceProjectionPolicyV1.sectionID == "evidence-assurance",
              ReportEvidenceAssuranceProjectionPolicyV1.sectionVersion == 1,
              ReportEvidenceAssuranceProjectionPolicyV1.projectionVersion
                    == "report-evidence-assurance-v1",
              ReportEvidenceAssuranceProjectionPolicyV1.previewRequired,
              ReportEvidenceAssuranceProjectionPolicyV1.manifestRequiredBeforeAttestation,
              ReportEvidenceAssuranceProjectionPolicyV1.excludesEvidenceContent,
              ReportEvidenceAssuranceProjectionPolicyV1.excludesActorPrivateDetail,
              ReportEvidenceAssuranceProjectionPolicyV1.excludesDeliveryAndRelease,
              ReportEvidenceAssuranceProjectionPolicyV1.supports(.openJSON),
              ReportEvidenceAssuranceProjectionPolicyV1.supports(.structuredText) else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try baseRendererRegistry.validate()
    }

    func semanticProjection(
        snapshot: CompletedActivitySnapshotV7,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        try validate()
        try snapshot.validate()
        try manifest.validate()
        let activity = snapshot.payload.activity
        let base = activity.payload.activity.activity.activity.activity.activity
        let binding = base.profileBinding
        guard binding.rendererVersion == baseRendererRegistry.soleRenderer,
              binding.sectionIDs.contains(ReportEvidenceAssuranceProjectionPolicyV1.sectionID),
              let section = manifest.reportSectionRegistry.sections.first(where: {
                  $0.sectionID == ReportEvidenceAssuranceProjectionPolicyV1.sectionID
              }),
              section.version == ReportEvidenceAssuranceProjectionPolicyV1.sectionVersion,
              section.privacyClass == ReportEvidenceAssuranceProjectionPolicyV1.privacyClass,
              ReportEvidenceAssuranceProjectionPolicyV1.supportedFormats.allSatisfy({
                  section.supportedFormats.contains($0)
              }),
              base.evidenceCards.allSatisfy({ $0.audience == binding.audience }) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        return try ReportSemanticProjectorV1.project(snapshot: snapshot, manifest: manifest)
    }

    /// Preview-only open JSON. The caller receives no publication bundle and
    /// must explicitly revalidate the source preview/manifest before any
    /// later release surface can act on it.
    func renderOpenJSON(
        snapshot: CompletedActivitySnapshotV7,
        manifest: ContractManifestV1
    ) throws -> ReportProjectionOutputV1 {
        let semantic = try semanticProjection(snapshot: snapshot, manifest: manifest)
        let output = try DeterministicOpenJSONRendererV1.render(semantic)
        guard try DeterministicOpenJSONRendererV1.reopen(output.data) == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return output
    }

    /// Preview-only accessible structured text. It is intentionally separate
    /// from any finalization producer and remains available as the textual
    /// fallback for the pre-S10 boundary.
    func renderStructuredText(
        snapshot: CompletedActivitySnapshotV7,
        manifest: ContractManifestV1
    ) throws -> ReportProjectionOutputV1 {
        let semantic = try semanticProjection(snapshot: snapshot, manifest: manifest)
        let output = try DeterministicOpenJSONRendererV1.renderStructuredText(semantic)
        guard try DeterministicOpenJSONRendererV1.reopenStructuredText(output.data) == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return output
    }
}

/// Additive C14 registry. It admits only the V8 completed snapshot with its
/// frozen inspection-review history and exposes preview/open-JSON and
/// structured-text projections. It deliberately has no finalization,
/// recovery, hosted, adoption, acceptance, or release authority.
struct ReportProjectionRegistryV8: Codable, Equatable, Sendable {
    static let schemaVersion = 8
    static let registryID = "report-projection-registry-v8"
    static let persistentContractSchema = "KERNEL_SNAPSHOT_V8"
    static let publicationDisposition = "PROVISIONAL_READ_ONLY_PRE_S10"
    static let nativeCompileRan = false
    static let hostedDispatchRan = false
    static let hostedDispatchEnabled = false
    static let adoptionEnabled = false
    static let acceptanceEnabled = false
    static let acceptanceCredit = false
    static let releaseCredit = false

    let schemaVersion: Int
    let registryID: String
    let persistentContractSchema: String
    let supportedPersistentContractSchemas: [String]
    let publicationDisposition: String
    let nativeCompileRan: Bool
    let hostedDispatchRan: Bool
    let adoptionEnabled: Bool
    let acceptanceCredit: Bool
    let releaseCredit: Bool
    let baseRendererRegistry: ReportProjectionRegistryV1

    init() {
        schemaVersion = Self.schemaVersion
        registryID = Self.registryID
        persistentContractSchema = Self.persistentContractSchema
        supportedPersistentContractSchemas = [
            "KERNEL_SNAPSHOT_V1", "KERNEL_SNAPSHOT_V2", "KERNEL_SNAPSHOT_V3",
            "KERNEL_SNAPSHOT_V4", "KERNEL_SNAPSHOT_V5", "KERNEL_SNAPSHOT_V6",
            "KERNEL_SNAPSHOT_V7", "KERNEL_SNAPSHOT_V8",
        ]
        publicationDisposition = Self.publicationDisposition
        nativeCompileRan = Self.nativeCompileRan
        hostedDispatchRan = Self.hostedDispatchRan
        adoptionEnabled = Self.adoptionEnabled
        acceptanceCredit = Self.acceptanceCredit
        releaseCredit = Self.releaseCredit
        baseRendererRegistry = ReportProjectionRegistryV1()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, registryID, persistentContractSchema
        case supportedPersistentContractSchemas, publicationDisposition
        case nativeCompileRan, hostedDispatchRan, adoptionEnabled
        case acceptanceCredit, releaseCredit, baseRendererRegistry
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let expected = Self()
        guard try values.decode(Int.self, forKey: .schemaVersion) == expected.schemaVersion,
              try values.decode(String.self, forKey: .registryID) == expected.registryID,
              try values.decode(String.self, forKey: .persistentContractSchema)
                    == expected.persistentContractSchema,
              try values.decode([String].self, forKey: .supportedPersistentContractSchemas)
                    == expected.supportedPersistentContractSchemas,
              try values.decode(String.self, forKey: .publicationDisposition)
                    == expected.publicationDisposition,
              try values.decode(Bool.self, forKey: .nativeCompileRan) == expected.nativeCompileRan,
              try values.decode(Bool.self, forKey: .hostedDispatchRan) == expected.hostedDispatchRan,
              try values.decode(Bool.self, forKey: .adoptionEnabled) == expected.adoptionEnabled,
              try values.decode(Bool.self, forKey: .acceptanceCredit) == expected.acceptanceCredit,
              try values.decode(Bool.self, forKey: .releaseCredit) == expected.releaseCredit,
              try values.decode(ReportProjectionRegistryV1.self, forKey: .baseRendererRegistry)
                    == expected.baseRendererRegistry else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        self = expected
    }

    func validate() throws {
        guard self == Self(),
              ReportInspectionReviewHistoryProjectionPolicyV1.sectionID
                    == "inspection-review-history",
              ReportInspectionReviewHistoryProjectionPolicyV1.sectionVersion == 1,
              ReportInspectionReviewHistoryProjectionPolicyV1.projectionVersion
                    == "report-inspection-review-history-v1",
              ReportInspectionReviewHistoryProjectionPolicyV1.requiredTypedLabels,
              ReportInspectionReviewHistoryProjectionPolicyV1.excludesClaims,
              ReportInspectionReviewHistoryProjectionPolicyV1.excludesTelemetry,
              ReportInspectionReviewHistoryProjectionPolicyV1.excludesOwnershipAndAuthorization,
              ReportInspectionReviewHistoryProjectionPolicyV1.excludesActorPrivateDetail,
              ReportInspectionReviewHistoryProjectionPolicyV1.supportsOpenJSON,
              ReportInspectionReviewHistoryProjectionPolicyV1.supportsStructuredText else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try baseRendererRegistry.validate()
    }

    func semanticProjection(
        snapshot: CompletedActivitySnapshotV8,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        try validate()
        try snapshot.validate()
        try manifest.validate()
        let v7 = snapshot.payload.activity
        let base = v7.payload.activity.payload.activity.activity.activity.activity.activity
        let binding = base.profileBinding
        guard binding.rendererVersion == baseRendererRegistry.soleRenderer,
              binding.sectionIDs.contains(ReportInspectionReviewHistoryProjectionPolicyV1.sectionID),
              let section = manifest.reportSectionRegistry.sections.first(where: {
                  $0.sectionID == ReportInspectionReviewHistoryProjectionPolicyV1.sectionID
              }),
              section.version == ReportInspectionReviewHistoryProjectionPolicyV1.sectionVersion,
              ReportInspectionReviewHistoryProjectionPolicyV1.supports(.openJSON),
              ReportInspectionReviewHistoryProjectionPolicyV1.supports(.structuredText),
              base.evidenceCards.allSatisfy({ $0.audience == binding.audience }) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        return try ReportSemanticProjectorV1.project(snapshot: snapshot, manifest: manifest)
    }

    func renderOpenJSON(
        snapshot: CompletedActivitySnapshotV8,
        manifest: ContractManifestV1
    ) throws -> ReportProjectionOutputV1 {
        let semantic = try semanticProjection(snapshot: snapshot, manifest: manifest)
        let output = try DeterministicOpenJSONRendererV1.render(semantic)
        guard try DeterministicOpenJSONRendererV1.reopen(output.data) == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return output
    }

    func renderStructuredText(
        snapshot: CompletedActivitySnapshotV8,
        manifest: ContractManifestV1
    ) throws -> ReportProjectionOutputV1 {
        let semantic = try semanticProjection(snapshot: snapshot, manifest: manifest)
        let output = try DeterministicOpenJSONRendererV1.renderStructuredText(semantic)
        guard try DeterministicOpenJSONRendererV1.reopenStructuredText(output.data) == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return output
    }
}

/// Additive C15 registry. It accepts only the V9 completed snapshot and emits
/// the read-only packet projection through the existing semantic renderer.
/// There is no finalization, recovery, hosted, adoption, acceptance, or
/// release authority in this registry.
struct ReportProjectionRegistryV9: Codable, Equatable, Sendable {
    static let schemaVersion = 9
    static let registryID = "report-projection-registry-v9"
    static let persistentContractSchema = "PERSISTENT_SCHEMA_V15_WORK_PACKET_COORDINATION"
    static let publicationDisposition = "PROVISIONAL_READ_ONLY_PRE_S10"
    static let nativeCompileRan = false
    static let hostedDispatchRan = false
    static let adoptionEnabled = false
    static let acceptanceCredit = false
    static let releaseCredit = false

    let schemaVersion: Int
    let registryID: String
    let persistentContractSchema: String
    let supportedPersistentContractSchemas: [String]
    let publicationDisposition: String
    let nativeCompileRan: Bool
    let hostedDispatchRan: Bool
    let adoptionEnabled: Bool
    let acceptanceCredit: Bool
    let releaseCredit: Bool
    let requiresAcceptedS10_6Reconciliation: Bool
    let baseRendererRegistry: ReportProjectionRegistryV1

    init() {
        schemaVersion = Self.schemaVersion
        registryID = Self.registryID
        persistentContractSchema = Self.persistentContractSchema
        supportedPersistentContractSchemas = [
            "KERNEL_SNAPSHOT_V1", "KERNEL_SNAPSHOT_V2", "KERNEL_SNAPSHOT_V3",
            "KERNEL_SNAPSHOT_V4", "KERNEL_SNAPSHOT_V5", "KERNEL_SNAPSHOT_V6",
            "KERNEL_SNAPSHOT_V7", "KERNEL_SNAPSHOT_V8", "KERNEL_SNAPSHOT_V9",
            Self.persistentContractSchema,
        ]
        publicationDisposition = Self.publicationDisposition
        nativeCompileRan = Self.nativeCompileRan
        hostedDispatchRan = Self.hostedDispatchRan
        adoptionEnabled = Self.adoptionEnabled
        acceptanceCredit = Self.acceptanceCredit
        releaseCredit = Self.releaseCredit
        requiresAcceptedS10_6Reconciliation = true
        baseRendererRegistry = ReportProjectionRegistryV1()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, registryID, persistentContractSchema
        case supportedPersistentContractSchemas, publicationDisposition
        case nativeCompileRan, hostedDispatchRan, adoptionEnabled
        case acceptanceCredit, releaseCredit, requiresAcceptedS10_6Reconciliation
        case baseRendererRegistry
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let expected = Self()
        guard try values.decode(Int.self, forKey: .schemaVersion) == expected.schemaVersion,
              try values.decode(String.self, forKey: .registryID) == expected.registryID,
              try values.decode(String.self, forKey: .persistentContractSchema)
                    == expected.persistentContractSchema,
              try values.decode([String].self, forKey: .supportedPersistentContractSchemas)
                    == expected.supportedPersistentContractSchemas,
              try values.decode(String.self, forKey: .publicationDisposition)
                    == expected.publicationDisposition,
              try values.decode(Bool.self, forKey: .nativeCompileRan) == expected.nativeCompileRan,
              try values.decode(Bool.self, forKey: .hostedDispatchRan) == expected.hostedDispatchRan,
              try values.decode(Bool.self, forKey: .adoptionEnabled) == expected.adoptionEnabled,
              try values.decode(Bool.self, forKey: .acceptanceCredit) == expected.acceptanceCredit,
              try values.decode(Bool.self, forKey: .releaseCredit) == expected.releaseCredit,
              try values.decode(Bool.self, forKey: .requiresAcceptedS10_6Reconciliation)
                    == expected.requiresAcceptedS10_6Reconciliation,
              try values.decode(ReportProjectionRegistryV1.self, forKey: .baseRendererRegistry)
                    == expected.baseRendererRegistry else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        self = expected
    }

    func validate() throws {
        guard self == Self(),
              ReportWorkPacketProjectionPolicyV1.sectionID == "work-packet",
              ReportWorkPacketProjectionPolicyV1.sectionVersion == 1,
              ReportWorkPacketProjectionPolicyV1.projectionVersion == "report-work-packet-v1",
              ReportWorkPacketProjectionPolicyV1.publicationDisposition
                    == Self.publicationDisposition,
              ReportWorkPacketProjectionPolicyV1.requiredTypedLabels,
              ReportWorkPacketProjectionPolicyV1.indexesCurrentHeadsOnly,
              ReportWorkPacketProjectionPolicyV1.excludesActorPrivateDetail,
              ReportWorkPacketProjectionPolicyV1.excludesResultAndEvidenceLinks,
              ReportWorkPacketProjectionPolicyV1.excludesClaimsAndAuthorization,
              ReportWorkPacketProjectionPolicyV1.excludesTelemetryAndDelivery,
              ReportWorkPacketProjectionPolicyV1.supports(.openJSON),
              ReportWorkPacketProjectionPolicyV1.supports(.structuredText) else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try baseRendererRegistry.validate()
    }

    func semanticProjection(
        snapshot: CompletedActivitySnapshotV9,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        try validate()
        try snapshot.validate()
        try manifest.validate()
        let v8 = snapshot.payload.activity
        let v7 = v8.payload.activity
        let v6 = v7.payload.activity
        let base = v6.payload.activity.activity.activity.activity.activity
        let binding = base.profileBinding
        guard binding.rendererVersion == baseRendererRegistry.soleRenderer,
              binding.sectionIDs.contains(ReportWorkPacketProjectionPolicyV1.sectionID),
              let section = manifest.reportSectionRegistry.sections.first(where: {
                  $0.sectionID == ReportWorkPacketProjectionPolicyV1.sectionID
              }),
              section.version == ReportWorkPacketProjectionPolicyV1.sectionVersion,
              section.privacyClass == ReportWorkPacketProjectionPolicyV1.privacyClass,
              ReportWorkPacketProjectionPolicyV1.supportedFormats.allSatisfy({
                  section.supportedFormats.contains($0)
              }),
              base.evidenceCards.allSatisfy({ $0.audience == binding.audience }) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        return try ReportSemanticProjectorV1.project(snapshot: snapshot, manifest: manifest)
    }

    func renderOpenJSON(
        snapshot: CompletedActivitySnapshotV9,
        manifest: ContractManifestV1
    ) throws -> ReportProjectionOutputV1 {
        let semantic = try semanticProjection(snapshot: snapshot, manifest: manifest)
        let output = try DeterministicOpenJSONRendererV1.render(semantic)
        guard try DeterministicOpenJSONRendererV1.reopen(output.data) == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return output
    }

    func renderStructuredText(
        snapshot: CompletedActivitySnapshotV9,
        manifest: ContractManifestV1
    ) throws -> ReportProjectionOutputV1 {
        let semantic = try semanticProjection(snapshot: snapshot, manifest: manifest)
        let output = try DeterministicOpenJSONRendererV1.renderStructuredText(semantic)
        guard try DeterministicOpenJSONRendererV1.reopenStructuredText(output.data) == semantic else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return output
    }
}

// C18 report consumers carry a frozen release identity and the small
// lifecycle metadata projection. They never carry package/workflow bytes or
// mutable draft state, so reopening a historical report cannot silently
// resolve it against a newer package.
struct PackageEvolutionFrozenReportBindingV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let packageID: String
    let packageReleaseID: String
    let packageSHA256: String
    let workflowSHA256: String
    let releaseState: InspectionPackageReleaseStateV1

    init(release: InspectionPackageReleaseV1) throws {
        try release.validate()
        guard release.state == .published else {
            throw PackageEvolutionConsumerFailureV1.mismatchedRelease
        }
        schemaVersion = Self.schemaVersion
        packageID = release.packageID
        packageReleaseID = release.packageReleaseID
        packageSHA256 = release.packageSHA256
        workflowSHA256 = release.workflowSHA256
        releaseState = release.state
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              InspectionPackageValidationV2.validIdentifier(packageID, maximumBytes: 200),
              KernelCanonicalHashV1.validSHA256(packageReleaseID),
              KernelCanonicalHashV1.validSHA256(packageSHA256),
              KernelCanonicalHashV1.validSHA256(workflowSHA256),
              releaseState == .published else {
            throw PackageEvolutionConsumerFailureV1.invalidMetadata
        }
    }

    func validate(against release: InspectionPackageReleaseV1) throws {
        try validate()
        try release.validate()
        guard release.state == .published,
              packageID == release.packageID,
              packageReleaseID == release.packageReleaseID,
              packageSHA256 == release.packageSHA256,
              workflowSHA256 == release.workflowSHA256,
              releaseState == release.state else {
            throw PackageEvolutionConsumerFailureV1.mismatchedRelease
        }
    }
}

struct PackageEvolutionReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let metadata: PackageEvolutionConsumerMetadataV1
    let frozenRelease: PackageEvolutionFrozenReportBindingV1

    init(
        metadata: PackageEvolutionConsumerMetadataV1,
        release: InspectionPackageReleaseV1
    ) throws {
        try metadata.validate()
        let frozen = try PackageEvolutionFrozenReportBindingV1(release: release)
        guard metadata.packageID == release.packageID,
              metadata.packageReleaseID == release.packageReleaseID else {
            throw PackageEvolutionConsumerFailureV1.mismatchedRelease
        }
        schemaVersion = Self.schemaVersion
        self.metadata = metadata
        frozenRelease = frozen
        try validate()
    }

    init(bundle: PackagePromotionAtomicBundleV1) throws {
        try self.init(
            metadata: PackageEvolutionConsumerMetadataV1(bundle: bundle),
            release: bundle.promotedRelease.packageRelease
        )
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw PackageEvolutionConsumerFailureV1.invalidMetadata
        }
        try metadata.validate()
        try frozenRelease.validate()
        guard metadata.packageID == frozenRelease.packageID,
              metadata.packageReleaseID == frozenRelease.packageReleaseID else {
            throw PackageEvolutionConsumerFailureV1.mismatchedRelease
        }
    }
}

enum PackageEvolutionReportConsumerPolicyV1 {
    static let requiredSandboxChecks: Set<PackageSandboxCheckKindV1> = [
        .localizedDisplay, .reportPDF, .openJSON, .replay,
    ]
    static let historicalReportsUseFrozenReleaseIdentity = true
    static let reportContainsCanonicalPackageBytes = false
    static let reportContainsDraftPayload = false
    static let reportReformatsOnLocaleChange = false

    static func validateSandbox(_ run: PackageSandboxRunV1) throws {
        try run.validate()
        guard run.disposition == .completePass,
              requiredSandboxChecks.allSatisfy({ required in
                  run.checks.contains { $0.kind == required && $0.disposition == .passed }
              }) else {
            throw PackageEvolutionConsumerFailureV1.incompleteSandbox
        }
    }
}

extension ReportProjectionRegistryV1 {
    static func packageEvolutionProjection(
        bundle: PackagePromotionAtomicBundleV1
    ) throws -> PackageEvolutionReportProjectionV1 {
        try PackageEvolutionReportConsumerPolicyV1.validateSandbox(bundle.sandboxRun)
        return try PackageEvolutionReportProjectionV1(bundle: bundle)
    }

    func validatePackageEvolutionSandbox(_ run: PackageSandboxRunV1) throws {
        try validate()
        try PackageEvolutionReportConsumerPolicyV1.validateSandbox(run)
    }
}

// MARK: - C29 versioned plan/rebase projection

extension ReportProjectionRegistryV1 {
    static let planProjectionSectionID = PlanReportProjectionPolicyV1.sectionID
    static let planProjectionVersion = PlanReportProjectionPolicyV1.projectionVersion

    func validatePlanProjection(
        _ projection: PlanReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> PlanReportProjectionV1 {
        try validate()
        try PlanContractManifestBoundaryV1.validate()
        return try PlanReportProjectionPolicyV1.validate(
            projection,
            format: format
        )
    }

    static func validatePlanProjection(
        _ projection: PlanReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> PlanReportProjectionV1 {
        try Self().validatePlanProjection(projection, format: format)
    }

    static func planProjection(
        document: PlanDocumentV1,
        revision: PlanRevisionV1,
        placements: [PlanPlacementV1],
        preview: RebasePreviewV1? = nil,
        receipt: RebaseReceiptV1? = nil
    ) throws -> PlanReportProjectionV1 {
        let projection = try PlanReportProjectionV1(
            document: document,
            revision: revision,
            placements: placements,
            preview: preview,
            receipt: receipt
        )
        return try validatePlanProjection(projection)
    }
}

// MARK: - C21 client capability and package lifecycle consumer enrollment

enum ClientCapabilityReportConsumerPolicyV1 {
    static let sectionID = ClientCapabilityReportProjectionPolicyV1.sectionID
    static let projectionVersion = ClientCapabilityReportProjectionPolicyV1.projectionVersion
    static let metadataOnly = true
    static let canonicalDecisionRequired = true
    static let withdrawalBlocksNewWork = true
    static let historicFinalizedArtifactsRemainExportable = true
    static let denyWriteUnlessReadWrite = true
    static let denyMigrationQuarantineRejectOperations = true
    static let immutableHistoricDisplay = true
    static let correctionsAreAmendOnly = true
    static let excludesDeviceIdentity = true
    static let excludesUserIdentity = true
    static let excludesEndpointProviderAccount = true
    static let excludesRemoteDeliveryAcknowledgement = true
    static let excludesPackagePayload = true
    static let readOperations: Set<PackageLifecycleOperationV1> = [
        .view, .export, .restore, .replay,
    ]
    static let writeOperations: Set<PackageLifecycleOperationV1> = [
        .start, .resume, .finalize, .amend, .upgradeDraft,
    ]

    static func validate(
        _ projection: ClientCapabilityReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws {
        try projection.validate()
        guard ClientCapabilityReportProjectionPolicyV1.supports(format),
              metadataOnly,
              canonicalDecisionRequired,
              withdrawalBlocksNewWork,
              historicFinalizedArtifactsRemainExportable,
              denyWriteUnlessReadWrite,
              denyMigrationQuarantineRejectOperations,
              immutableHistoricDisplay,
              correctionsAreAmendOnly,
              excludesDeviceIdentity,
              excludesUserIdentity,
              excludesEndpointProviderAccount,
              excludesRemoteDeliveryAcknowledgement,
              excludesPackagePayload else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
    }

    static func require(
        _ projection: ClientCapabilityReportProjectionV1,
        operation: PackageLifecycleOperationV1,
        allowsWrite: Bool
    ) throws {
        let operationSet = allowsWrite ? writeOperations : readOperations
        guard projection.operation == operation,
              operationSet.contains(operation),
              projection.operationAllowed,
              (!allowsWrite || projection.writeAllowed),
              (allowsWrite || projection.readAllowed) else {
            throw ClientCapabilityReportProjectionFailureV1.admissionDenied
        }
    }

    static func allowsHistoricExport(
        _ projection: ClientCapabilityReportProjectionV1
    ) -> Bool {
        projection.historicExportAllowed
    }
}

extension ReportProjectionRegistryV1 {
    func validateClientCapabilityConsumer(
        _ projection: ClientCapabilityReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws {
        try validate()
        try ClientCapabilityReportConsumerPolicyV1.validate(projection, format: format)
    }

    static func validateClientCapabilityConsumer(
        _ projection: ClientCapabilityReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws {
        try Self().validateClientCapabilityConsumer(projection, format: format)
    }

    static func clientCapabilityProjection(
        decision: ClientCapabilityAdmissionDecisionV1,
        profile: ClientCapabilityProfileV1,
        policy: PackageLifecyclePolicyV1,
        disposition: PackageLifecycleDispositionV1,
        release: InspectionPackageReleaseV1
    ) throws -> ClientCapabilityReportProjectionV1 {
        let projection = try ClientCapabilityReportProjectionV1(
            decision: decision,
            profile: profile,
            policy: policy,
            disposition: disposition,
            release: release
        )
        try validateClientCapabilityConsumer(projection, format: .openJSON)
        return projection
    }
}

/// C19 report consumers use one frozen measurement projection for every
/// supported output. This policy is intentionally a projection gate rather
/// than a second measurement writer.
enum MeasurementIntegrityReportConsumerPolicyV1 {
    static let sectionID = ReportMeasurementIntegrityProjectionPolicyV1.sectionID
    static let sectionVersion = ReportMeasurementIntegrityProjectionPolicyV1.sectionVersion
    static let projectionVersion = ReportMeasurementIntegrityProjectionPolicyV1.projectionVersion
    static let historicalValuesRemainFrozen = true
    static let unitMeaningRemainsFrozen = true
    static let excludesOpaqueSerial = true
    static let excludesOperatorIdentity = true
    static let excludesRawResponse = true
    static let excludesEvidenceLocators = true

    static func validate(
        _ projection: MeasurementIntegrityReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws {
        try projection.validate()
        guard ReportMeasurementIntegrityProjectionPolicyV1.supports(format),
              historicalValuesRemainFrozen, unitMeaningRemainsFrozen,
              excludesOpaqueSerial, excludesOperatorIdentity,
              excludesRawResponse, excludesEvidenceLocators else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        try EvidenceDetailMeasurementIntegrityProjectionGuardV1.validate(projection)
    }
}

extension ReportProjectionRegistryV1 {
    func validateMeasurementIntegrityConsumer(
        _ projection: MeasurementIntegrityReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws {
        try validate()
        guard requiredFormats.contains(format) else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try MeasurementIntegrityReportConsumerPolicyV1.validate(projection, format: format)
    }

    static func validateMeasurementIntegrityConsumer(
        _ projection: MeasurementIntegrityReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws {
        try Self().validateMeasurementIntegrityConsumer(projection, format: format)
    }
}

// MARK: - C20 privacy-transform consumer enrollment

enum PrivacyTransformReportConsumerPolicyV1 {
    static let sectionID = PrivacyTransformReportProjectionPolicyV1.sectionID
    static let projectionVersion = PrivacyTransformReportProjectionPolicyV1.projectionVersion
    static let approvedDerivativeOnly = true
    static let denyOriginalAccessByProjection = true
    static let requiresExplicitRedactionDeclaration = true
    static let historicalReportsUseFrozenBinding = true
    static let correctionsAreAmendOnly = true
    static let excludesOriginalReferences = true
    static let excludesOriginalBytes = true
    static let excludesDerivativeBytes = true
    static let excludesReviewerIdentity = true
    static let excludesReviewRationale = true

    static func validate(
        _ projection: PrivacyTransformReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws {
        try projection.validate()
        guard PrivacyTransformReportProjectionPolicyV1.supports(format),
              approvedDerivativeOnly,
              denyOriginalAccessByProjection,
              requiresExplicitRedactionDeclaration,
              historicalReportsUseFrozenBinding,
              correctionsAreAmendOnly,
              excludesOriginalReferences,
              excludesOriginalBytes,
              excludesDerivativeBytes,
              excludesReviewerIdentity,
              excludesReviewRationale,
              projection.isAudienceSafe else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        try EvidenceDetailPrivacyTransformProjectionGuardV1.validate(
            projection,
            audience: projection.reportAudience ?? .customerSafe
        )
    }
}

extension ReportProjectionRegistryV1 {
    func validatePrivacyTransformConsumer(
        _ projection: PrivacyTransformReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws {
        try validate()
        try PrivacyTransformReportConsumerPolicyV1.validate(projection, format: format)
    }

    static func validatePrivacyTransformConsumer(
        _ projection: PrivacyTransformReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws {
        try Self().validatePrivacyTransformConsumer(projection, format: format)
    }

    static func privacyTransformProjection(
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        audience: ReportAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        redactionDeclared: Bool,
        now: Date = Date()
    ) throws -> PrivacyTransformReportProjectionV1 {
        let projection = try PrivacyTransformReportProjectionV1(
            manifest: manifest,
            review: review,
            policy: policy,
            audience: audience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            redactionDeclared: redactionDeclared,
            now: now
        )
        try validatePrivacyTransformConsumer(projection, format: .openJSON)
        return projection
    }
}

// MARK: - C23 version-bound field-reference consumer

extension ReportProjectionRegistryV1 {
    func validateFieldReferenceConsumer(
        _ projection: FieldReferenceReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> FieldReferenceReportProjectionV1 {
        try validate()
        return try FieldReferenceReportProjectionPolicyV1.validate(
            projection,
            format: format
        )
    }

    static func validateFieldReferenceConsumer(
        _ projection: FieldReferenceReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> FieldReferenceReportProjectionV1 {
        try Self().validateFieldReferenceConsumer(projection, format: format)
    }

    static let fieldReferenceProjectionSectionID =
        FieldReferenceReportProjectionPolicyV1.sectionID
}

// MARK: - C25 survey-definition report projection

extension ReportProjectionRegistryV1 {
    static let surveyDefinitionProjectionSectionID = "survey.definition"
    static let surveyDefinitionProjectionVersion =
        SurveyDefinitionConsumerPolicyV1.projectionVersion

    func validateSurveyDefinitionProjection(
        _ projection: SurveyDefinitionReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> SurveyDefinitionReportProjectionV1 {
        try validate()
        try projection.validate(format: format)
        try SurveyDefinitionContractManifestBoundaryV1.validate()
        return projection
    }

    static func validateSurveyDefinitionProjection(
        _ projection: SurveyDefinitionReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> SurveyDefinitionReportProjectionV1 {
        try Self().validateSurveyDefinitionProjection(projection, format: format)
    }

    static func surveyDefinitionProjection(
        release: SurveyDefinitionReleaseV1,
        lifecycleState: SurveyDefinitionLifecycleStateV1
    ) throws -> SurveyDefinitionReportProjectionV1 {
        let projection = try SurveyDefinitionReportProjectionV1(
            release: release,
            lifecycleState: lifecycleState
        )
        return try validateSurveyDefinitionProjection(projection)
    }
}

// MARK: - C27 asset-locator report projection

extension ReportProjectionRegistryV1 {
    static let assetLocatorProjectionSectionID =
        AssetLocatorReportProjectionPolicyV1.sectionID
    static let assetLocatorProjectionVersion =
        AssetLocatorReportProjectionPolicyV1.projectionVersion

    func validateAssetLocatorProjection(
        _ projection: AssetLocatorReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> AssetLocatorReportProjectionV1 {
        try validate()
        try AssetLocatorReportProjectionPolicyV1.validate()
        guard AssetLocatorReportProjectionPolicyV1.supports(format) else {
            throw AssetLocatorReportProjectionFailureV1.unsupportedFormat
        }
        return try EvidenceDetailAssetLocatorProjectionGuardV1.validate(projection)
    }

    static func validateAssetLocatorProjection(
        _ projection: AssetLocatorReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> AssetLocatorReportProjectionV1 {
        try Self().validateAssetLocatorProjection(projection, format: format)
    }

    static func assetLocatorProjection(
        locator: AssetLocatorV1,
        resolution: LocatorResolutionV1? = nil,
        frozenInterpretation: FrozenAssetLocatorInterpretationV1? = nil
    ) throws -> AssetLocatorReportProjectionV1 {
        let projection = try AssetLocatorReportProjectionV1(
            locator: locator,
            resolution: resolution,
            frozenInterpretation: frozenInterpretation
        )
        return try validateAssetLocatorProjection(projection)
    }
}

// MARK: - C28 schedule and occurrence projection

extension ReportProjectionRegistryV1 {
    static let scheduleProjectionSectionID = ScheduleReportProjectionPolicyV1.sectionID
    static let scheduleProjectionVersion = ScheduleReportProjectionPolicyV1.projectionVersion

    func validateScheduleProjection(
        _ projection: ScheduleReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> ScheduleReportProjectionV1 {
        try validate()
        try ScheduleReportProjectionPolicyV1.validate(projection, format: format)
        try ScheduleContractManifestBoundaryV1.validate()
        return projection
    }

    static func validateScheduleProjection(
        _ projection: ScheduleReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> ScheduleReportProjectionV1 {
        try Self().validateScheduleProjection(projection, format: format)
    }

    static func scheduleProjection(
        definition: ScheduleDefinitionReleaseV1,
        dueQueue: DueQueueProjectionV1,
        history: [OccurrenceHistoryEventV1],
        reminder: ReminderProjectionV1? = nil
    ) throws -> ScheduleReportProjectionV1 {
        let projection = try ScheduleReportProjectionV1(
            definition: definition,
            dueQueue: dueQueue,
            history: history,
            reminder: reminder
        )
        return try validateScheduleProjection(projection)
    }
}

// MARK: - C37 reference-framed pose projection

extension ReportProjectionRegistryV1 {
    static let placementPoseProjectionSectionID = "pose"
    static let placementPoseProjectionVersion =
        C37PlacementPoseReportProjectionV1.projectionVersion

    func validatePlacementPoseProjection(
        _ projection: C37PlacementPoseReportProjectionV1
    ) throws -> C37PlacementPoseReportProjectionV1 {
        try validate()
        try C37PoseReportProjectionPolicyV1.validate(projection)
        return projection
    }

    static func validatePlacementPoseProjection(
        _ projection: C37PlacementPoseReportProjectionV1
    ) throws -> C37PlacementPoseReportProjectionV1 {
        try Self().validatePlacementPoseProjection(projection)
    }

    static func placementPoseProjection(
        workspaceID: WorkspaceID,
        assetID: UUID,
        events: [AssetPoseEventV1],
        capturedAt: Date
    ) throws -> C37PlacementPoseReportProjectionV1 {
        let projection = try C37PlacementPoseReportProjectionV1(
            workspaceID: workspaceID,
            assetID: assetID,
            events: events,
            capturedAt: capturedAt
        )
        return try validatePlacementPoseProjection(projection)
    }
}
// MARK: - C30 operating-context registry

extension ReportProjectionRegistryV1 {
    static let c30OperatingContextProjectionVersion =
        C30EvidenceContextReportReferenceV1.schemaVersion
    static let c30OperatingContextProjectionIsFrozen = true
    static let c30OperatingContextPreservesOriginals = true

    static func validateOperatingContextProjection(
        _ projection: C30EvidenceContextReportReferenceV1
    ) throws -> C30EvidenceContextReportReferenceV1 {
        try C30OperatingContextConsumerPolicyV1.validate(projection)
        return projection
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Reporting_ReportProjectionRegistryV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift", role: .report)
}

// MARK: - C31 lighting projection registration

enum C31LightingReportProjectionRegistryV1 {
    static let contractID = "lighting.report.projection.v1"
    static let metadataOnly = true
    static let historicDisplayFrozen = true
    static let actorIdentityExcluded = true
    static let bytesAndPrivateLocatorsExcluded = true
    static let forbiddenOperationalInference = true

    static func validate(
        _ projection: C31LightingReportProjectionV1
    ) throws -> C31LightingReportProjectionV1 {
        try C31LightingProjectionPolicyV1.validate(projection)
        return projection
    }
}

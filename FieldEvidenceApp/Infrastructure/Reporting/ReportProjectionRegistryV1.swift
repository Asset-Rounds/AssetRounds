import Foundation

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
        snapshotID = snapshot.payload.snapshotID
        snapshotSHA256 = snapshot.snapshotSHA256
        self.semanticProjection = semanticProjection
        self.pdf = pdf
        self.openJSON = openJSON
        self.structuredText = structuredText
        artifactSetSHA256 = KernelCanonicalHashV1.sha256(Data(artifactRows.utf8))
        accessibleStructuredTextAlwaysPresent = true
        taggedPDFAccessibilityClaimed = false
        requiresFinalAudienceConfirmation = snapshot.payload.profileBinding.audience == .customerSafe
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
}

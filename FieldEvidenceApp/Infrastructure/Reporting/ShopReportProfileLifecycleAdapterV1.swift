import Foundation

/// Local-only C04 handoff boundary with no storage or presentation side effect.
/// Downstream consumers must reopen the exact local bytes named by its receipt.
enum ShopReportProfileLifecycleAdapterV1 {
    static let detectorID = "shop-report-post-markup-privacy"
    static let detectorVersion = 1
    static let maximumBulkHandoffs = 32
    static let maximumCSVRows = ShopReportProfileLimitsV1.maximumMediaItems
    static let maximumCSVColumns = ShopReportProfileLimitsV1.maximumTextBytes

    struct ArtifactInput: Equatable, Sendable {
        let format: ReportProjectionFormatV1
        let bytes: Data

        init(format: ReportProjectionFormatV1, bytes: Data) {
            self.format = format
            self.bytes = bytes
        }
    }

    struct PreparedHandoff: Equatable, Sendable {
        let composedBytes: Data
        let detection: PostMarkupAudiencePrivacyDetectionV1
        let confirmation: FinalAudiencePrivacyConfirmationV1
        let detailReceipt: EvidenceDetailCardRenderReceiptV1
        let accessibleTree: AccessibleDocumentSemanticTreeV1
        let accessibleAssessment: AccessibleDocumentAssessmentReceiptV1
        let confirmedFormat: ReportProjectionFormatV1
        let formulaSafeCSVRows: [[String]]
        let handoff: ShopOpenEvidenceHandoffReceiptV1
    }

    /// A profile is immutable at handoff time. Any current-profile change must
    /// produce a new frontier and therefore invalidates a prior receipt.
    static func freeze(
        _ profile: ShopReportProfileV1,
        sectionRegistry: ReportSectionRegistryV1
    ) throws -> ShopReportProfileReferenceV1 {
        try profile.validate(sectionRegistry: sectionRegistry)
        guard profile.activation == .on else {
            throw ShopReportProfileFailureV1.profileMismatch
        }
        return try profile.reference
    }

    @MainActor
    static func prepare(
        coordinator: ShopReportProfileCoordinatorV1,
        profile: ShopReportProfileV1,
        sectionRegistry: ReportSectionRegistryV1,
        finalizedBinding: FinalizedReportProfileBindingV1,
        snapshotID: String,
        sourceSnapshotSHA256: String,
        semanticSHA256: String,
        semanticText: String,
        card: EvidenceDetailCardV1,
        artifacts: [ArtifactInput],
        media: [OutputScopedContentReferenceV1],
        confirmedFormat: ReportProjectionFormatV1,
        formulaSafeCSVRows: [[String]],
        accessibleTree: AccessibleDocumentSemanticTreeV1,
        accessibleAssessment: AccessibleDocumentAssessmentReceiptV1,
        accessibleOutput: AccessibleDocumentRenderOutputV1,
        confirmationID: String,
        receiptID: String,
        userConfirmedExactComposedBytes: Bool
    ) throws -> PreparedHandoff {
        let frontier = try freeze(profile, sectionRegistry: sectionRegistry)
        guard let currentProfile = try coordinator.current(profileID: profile.profileID),
              currentProfile == profile else {
            throw ShopReportProfileFailureV1.staleRevision
        }
        try finalizedBinding.validate()
        try card.validate()
        try media.forEach { try $0.validate() }
        try accessibleTree.validate()
        try accessibleAssessment.validate(tree: accessibleTree)
        try accessibleAssessment.validateOutput(accessibleOutput.bytes)
        guard profile.reportLayoutProfile.audience == .customerSafe,
              finalizedBinding.audience == .customerSafe,
              card.audience == profile.reportLayoutProfile.audience,
              card.profileSHA256 == (try ShopReportProfileCanonicalCodecV1.sha256(profile.evidenceDetailProfile)),
              card.localeIdentifier == profile.reportLayoutProfile.localeIdentifier,
              card.displayProfileID == profile.reportLayoutProfile.displayProfileID,
              card.rendererVersion == profile.rendererVersion,
              confirmedFormat != .manifest,
              artifacts.map(\.format).sorted(by: { $0.rawValue < $1.rawValue })
                == [.formulaSafeCSV, .openJSON, .pdf, .structuredText],
              Set(artifacts.map(\.format)).count == artifacts.count,
              media.count <= ShopReportProfileLimitsV1.maximumMediaItems,
              media == media.sorted(),
              media.allSatisfy({ card.outputReferences.contains($0) }),
              profile.revision <= UInt64(Int.max),
              accessibleTree.workspaceID == profile.workspaceID,
              accessibleTree.audience == finalizedBinding.audience,
              accessibleTree.projectionVersion == finalizedBinding.projectionVersion,
              accessibleTree.publication.snapshotSHA256 == sourceSnapshotSHA256,
              accessibleTree.publication.manifestID == finalizedBinding.contractManifestID,
              accessibleTree.publication.manifestVersion == finalizedBinding.contractManifestVersion,
              accessibleTree.publication.manifestSHA256 == finalizedBinding.contractManifestSHA256,
              accessibleTree.publication.localeIdentifier == finalizedBinding.localeIdentifier,
              accessibleTree.publication.profileID == finalizedBinding.reportProfileID,
              accessibleTree.publication.profileRelease == finalizedBinding.reportProfileRelease,
              accessibleTree.publication.profileSHA256 == finalizedBinding.reportProfileSHA256,
              accessibleTree.publication.brandProfileID == profile.profileID.uuidString.lowercased(),
              accessibleTree.publication.brandProfileRelease == Int(profile.revision),
              accessibleTree.publication.brandProfileSHA256 == profile.profileSHA256,
              accessibleAssessment.workspaceID == profile.workspaceID,
              accessibleAssessment.snapshotSHA256 == sourceSnapshotSHA256,
              accessibleAssessment.audience == finalizedBinding.audience,
              accessibleAssessment.manifestID == finalizedBinding.contractManifestID,
              accessibleAssessment.manifestVersion == finalizedBinding.contractManifestVersion,
              accessibleAssessment.manifestSHA256 == finalizedBinding.contractManifestSHA256,
              accessibleAssessment.localeIdentifier == finalizedBinding.localeIdentifier,
              accessibleAssessment.profileID == finalizedBinding.reportProfileID,
              accessibleAssessment.profileRelease == finalizedBinding.reportProfileRelease,
              accessibleAssessment.profileSHA256 == finalizedBinding.reportProfileSHA256,
              accessibleAssessment.brandProfileID == profile.profileID.uuidString.lowercased(),
              accessibleAssessment.brandProfileRelease == Int(profile.revision),
              accessibleAssessment.brandProfileSHA256 == profile.profileSHA256,
              accessibleAssessment.rendererID == accessibleOutput.rendererID,
              accessibleAssessment.rendererVersion == accessibleOutput.rendererVersion,
              accessibleAssessment.outputMediaType == accessibleOutput.mediaType,
              accessibleOutput.rendererVersion == profile.rendererVersion else {
            throw ShopReportProfileFailureV1.artifactMismatch
        }

        let exactArtifacts = try artifacts.map {
            try ShopOpenEvidenceArtifactV1(format: $0.format, bytes: $0.bytes)
        }.sorted { $0.format.rawValue < $1.format.rawValue }
        try validateExistingRendererArtifacts(
            exactArtifacts,
            formulaSafeCSVRows: formulaSafeCSVRows
        )
        let detections = try exactArtifacts.map { artifact in
            try EvidenceDetailComposerV1.detectPostMarkupPrivacy(
                card: card,
                policy: card.audiencePrivacyPolicy,
                semanticText: semanticText,
                composedOutput: artifact.bytes,
                detectorID: detectorID,
                detectorVersion: detectorVersion
            )
        }
        let accessibilityDetection = try EvidenceDetailComposerV1.detectPostMarkupPrivacy(
            card: card,
            policy: card.audiencePrivacyPolicy,
            semanticText: semanticText,
            composedOutput: accessibleOutput.bytes,
            detectorID: detectorID,
            detectorVersion: detectorVersion
        )
        guard detections.allSatisfy({ $0.disposition == .pass }),
              accessibilityDetection.disposition == .pass,
              let selectedArtifact = exactArtifacts.first(where: { $0.format == confirmedFormat }),
              let detection = detections.first(where: { $0.composedOutputSHA256 == selectedArtifact.sha256 }) else {
            throw ShopReportProfileFailureV1.privacyConfirmationRequired
        }
        let composedBytes = selectedArtifact.bytes
        let confirmation = try FinalAudiencePrivacyConfirmationV1(
            confirmationID: confirmationID,
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            semanticSHA256: semanticSHA256,
            composedOutputSHA256: KernelCanonicalHashV1.sha256(composedBytes),
            card: card,
            detection: detection,
            userConfirmedExactComposedBytes: userConfirmedExactComposedBytes
        )
        let detailReceipt = try EvidenceDetailCardRenderReceiptV1(
            receiptID: receiptID,
            snapshotID: snapshotID,
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            semanticSHA256: semanticSHA256,
            card: card,
            composedOutputSHA256: KernelCanonicalHashV1.sha256(composedBytes),
            confirmation: confirmation
        )
        let manifestArtifact = try hashManifestArtifact(
            profile: profile,
            finalizedBinding: finalizedBinding,
            detailReceipt: detailReceipt,
            confirmation: confirmation,
            contentArtifacts: exactArtifacts,
            media: media,
            packaging: profile.packaging,
            accessibleAssessment: accessibleAssessment,
            accessibleOutput: accessibleOutput
        )
        let handoffArtifacts = (exactArtifacts + [manifestArtifact])
            .sorted { $0.format.rawValue < $1.format.rawValue }
        let handoff = try coordinator.prepareOpenEvidenceHandoff(
            profileID: profile.profileID,
            input: .init(
                finalizedBinding: finalizedBinding,
                detailReceipt: detailReceipt,
                confirmation: confirmation,
                artifacts: handoffArtifacts,
                media: media,
                packaging: profile.packaging,
                confirmedFormat: confirmedFormat,
                accessibleAssessment: accessibleAssessment,
                accessibleOutput: accessibleOutput
            )
        )
        guard handoff.profileFrontier == frontier else {
            throw ShopReportProfileFailureV1.staleRevision
        }
        return .init(
            composedBytes: composedBytes,
            detection: detection,
            confirmation: confirmation,
            detailReceipt: detailReceipt,
            accessibleTree: accessibleTree,
            accessibleAssessment: accessibleAssessment,
            confirmedFormat: confirmedFormat,
            formulaSafeCSVRows: formulaSafeCSVRows,
            handoff: handoff
        )
    }

    /// Formula cells are neutralized before quoting. This serializer is a
    /// separately-bound artifact; it is never substituted for OpenJSON.
    static func formulaSafeCSV(rows: [[String]]) throws -> Data {
        guard !rows.isEmpty,
              rows.count <= maximumCSVRows,
              rows.allSatisfy({ !$0.isEmpty }),
              rows.allSatisfy({ $0.count <= maximumCSVColumns }),
              rows.allSatisfy({ $0.count == rows[0].count }),
              rows.flatMap({ $0 }).allSatisfy({
                  SnapshotProjectionValidationV1.validText($0)
                      && $0.utf8.count <= ShopReportProfileLimitsV1.maximumTextBytes
              }) else {
            throw ShopReportProfileFailureV1.invalidValue
        }
        let csv = rows.map { row in
            row.map(formulaSafeField).joined(separator: ",")
        }.joined(separator: "\r\n").appending("\r\n")
        let data = Data(csv.utf8)
        guard data.count <= ShopReportProfileLimitsV1.maximumArtifactBytes else {
            throw ShopReportProfileFailureV1.limitExceeded
        }
        return data
    }

    static func prepareBulk(_ requests: [() throws -> PreparedHandoff]) throws -> [PreparedHandoff] {
        guard !requests.isEmpty, requests.count <= maximumBulkHandoffs else {
            throw ShopReportProfileFailureV1.limitExceeded
        }
        return try requests.map { try $0() }
    }

    /// Reopening is local validation only. A changed profile frontier, bytes,
    /// audience, display, locale, renderer, or semantic-tree assessment cannot
    /// retain an earlier confirmation.
    @MainActor
    static func reopen(
        _ prepared: PreparedHandoff,
        coordinator: ShopReportProfileCoordinatorV1,
        sectionRegistry: ReportSectionRegistryV1
    ) throws -> PreparedHandoff {
        guard let currentProfile = try coordinator.current(profileID: prepared.handoff.profileFrontier.profileID) else {
            throw ShopReportProfileFailureV1.staleRevision
        }
        let currentFrontier = try freeze(currentProfile, sectionRegistry: sectionRegistry)
        guard prepared.handoff.profileFrontier == currentFrontier,
              prepared.handoff.confirmedFormat == prepared.confirmedFormat,
              prepared.confirmedFormat != .manifest,
              prepared.handoff.detailReceipt == prepared.detailReceipt,
              prepared.handoff.confirmation == prepared.confirmation,
              prepared.handoff.accessibleAssessment == prepared.accessibleAssessment,
              !prepared.handoff.externalOpenClaimed,
              !prepared.handoff.deliveryClaimed else {
            throw ShopReportProfileFailureV1.staleRevision
        }
        try prepared.confirmation.validate()
        try prepared.detailReceipt.validate()
        try prepared.accessibleTree.validate()
        try prepared.accessibleAssessment.validate(tree: prepared.accessibleTree)
        try prepared.accessibleAssessment.validateOutput(prepared.handoff.accessibleOutput.bytes)
        try validateExistingRendererArtifacts(
            prepared.handoff.artifacts,
            formulaSafeCSVRows: prepared.formulaSafeCSVRows
        )
        try validateHashManifestArtifact(
            profile: currentProfile,
            finalizedBinding: prepared.handoff.finalizedBinding,
            detailReceipt: prepared.detailReceipt,
            confirmation: prepared.confirmation,
            artifacts: prepared.handoff.artifacts,
            media: prepared.handoff.media,
            packaging: prepared.handoff.packaging,
            accessibleAssessment: prepared.accessibleAssessment,
            accessibleOutput: prepared.handoff.accessibleOutput
        )
        guard prepared.handoff.finalizedBinding.audience == .customerSafe,
              currentProfile.revision <= UInt64(Int.max),
              prepared.accessibleTree.workspaceID == currentProfile.workspaceID,
              prepared.accessibleTree.audience == prepared.handoff.finalizedBinding.audience,
              prepared.accessibleTree.projectionVersion == prepared.handoff.finalizedBinding.projectionVersion,
              prepared.accessibleTree.publication.snapshotSHA256 == prepared.detailReceipt.sourceSnapshotSHA256,
              prepared.accessibleTree.publication.manifestID == prepared.handoff.finalizedBinding.contractManifestID,
              prepared.accessibleTree.publication.manifestVersion == prepared.handoff.finalizedBinding.contractManifestVersion,
              prepared.accessibleTree.publication.manifestSHA256 == prepared.handoff.finalizedBinding.contractManifestSHA256,
              prepared.accessibleTree.publication.localeIdentifier == prepared.handoff.finalizedBinding.localeIdentifier,
              prepared.accessibleTree.publication.profileID == prepared.handoff.finalizedBinding.reportProfileID,
              prepared.accessibleTree.publication.profileRelease == prepared.handoff.finalizedBinding.reportProfileRelease,
              prepared.accessibleTree.publication.profileSHA256 == prepared.handoff.finalizedBinding.reportProfileSHA256,
              prepared.accessibleTree.publication.brandProfileID == currentProfile.profileID.uuidString.lowercased(),
              prepared.accessibleTree.publication.brandProfileRelease == Int(currentProfile.revision),
              prepared.accessibleTree.publication.brandProfileSHA256 == currentProfile.profileSHA256,
              prepared.accessibleAssessment.workspaceID == currentProfile.workspaceID,
              prepared.accessibleAssessment.snapshotSHA256 == prepared.detailReceipt.sourceSnapshotSHA256,
              prepared.accessibleAssessment.audience == prepared.handoff.finalizedBinding.audience,
              prepared.accessibleAssessment.manifestID == prepared.handoff.finalizedBinding.contractManifestID,
              prepared.accessibleAssessment.manifestVersion == prepared.handoff.finalizedBinding.contractManifestVersion,
              prepared.accessibleAssessment.manifestSHA256 == prepared.handoff.finalizedBinding.contractManifestSHA256,
              prepared.accessibleAssessment.localeIdentifier == prepared.handoff.finalizedBinding.localeIdentifier,
              prepared.accessibleAssessment.profileID == prepared.handoff.finalizedBinding.reportProfileID,
              prepared.accessibleAssessment.profileRelease == prepared.handoff.finalizedBinding.reportProfileRelease,
              prepared.accessibleAssessment.profileSHA256 == prepared.handoff.finalizedBinding.reportProfileSHA256,
              prepared.accessibleAssessment.brandProfileID == currentProfile.profileID.uuidString.lowercased(),
              prepared.accessibleAssessment.brandProfileRelease == Int(currentProfile.revision),
              prepared.accessibleAssessment.brandProfileSHA256 == currentProfile.profileSHA256,
              prepared.accessibleAssessment.rendererID == prepared.handoff.accessibleOutput.rendererID,
              prepared.accessibleAssessment.rendererVersion == prepared.handoff.accessibleOutput.rendererVersion,
              prepared.accessibleAssessment.outputMediaType == prepared.handoff.accessibleOutput.mediaType else {
            throw ShopReportProfileFailureV1.artifactMismatch
        }
        guard let confirmedArtifact = prepared.handoff.artifacts.first(where: {
            $0.format == prepared.confirmedFormat
        }) else {
            throw ShopReportProfileFailureV1.artifactMismatch
        }
        let composedBytes = confirmedArtifact.bytes
        let artifactDetections = try prepared.handoff.artifacts.filter {
            $0.format != .manifest
        }.map { artifact in
            try EvidenceDetailComposerV1.detectPostMarkupPrivacy(
                card: prepared.confirmation.card,
                policy: prepared.confirmation.card.audiencePrivacyPolicy,
                semanticText: prepared.detection.semanticText,
                composedOutput: artifact.bytes,
                detectorID: detectorID,
                detectorVersion: detectorVersion
            )
        }
        let accessibilityDetection = try EvidenceDetailComposerV1.detectPostMarkupPrivacy(
            card: prepared.confirmation.card,
            policy: prepared.confirmation.card.audiencePrivacyPolicy,
            semanticText: prepared.detection.semanticText,
            composedOutput: prepared.handoff.accessibleOutput.bytes,
            detectorID: detectorID,
            detectorVersion: detectorVersion
        )
        guard prepared.composedBytes == composedBytes,
              prepared.detection.composedOutput == composedBytes,
              prepared.detection.composedOutputSHA256 == confirmedArtifact.sha256,
              artifactDetections.allSatisfy({ $0.disposition == .pass }),
              accessibilityDetection.disposition == .pass,
              prepared.confirmation.composedOutputSHA256 == KernelCanonicalHashV1.sha256(composedBytes),
              prepared.detailReceipt.composedOutputSHA256 == KernelCanonicalHashV1.sha256(composedBytes) else {
            throw ShopReportProfileFailureV1.artifactMismatch
        }
        let rebuilt = try coordinator.prepareOpenEvidenceHandoff(
            profileID: currentProfile.profileID,
            input: .init(
                finalizedBinding: prepared.handoff.finalizedBinding,
                detailReceipt: prepared.detailReceipt,
                confirmation: prepared.confirmation,
                artifacts: prepared.handoff.artifacts,
                media: prepared.handoff.media,
                packaging: prepared.handoff.packaging,
                confirmedFormat: prepared.confirmedFormat,
                accessibleAssessment: prepared.accessibleAssessment,
                accessibleOutput: prepared.handoff.accessibleOutput
            )
        )
        guard rebuilt == prepared.handoff else {
            throw ShopReportProfileFailureV1.artifactMismatch
        }
        return prepared
    }

    private static func formulaSafeField(_ value: String) -> String {
        let protected = firstSignificantScalar(in: value).map {
            "=+-@".unicodeScalars.contains($0)
        } == true ? "'\(value)" : value
        return "\"\(protected.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func firstSignificantScalar(in value: String) -> Unicode.Scalar? {
        value.unicodeScalars.first(where: { !isIgnorableFormulaPrefix($0) })
    }

    private static func isIgnorableFormulaPrefix(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0009...0x000D, 0x0020, 0x00A0, 0x1680, 0x180E,
             0x2000...0x200F, 0x2028, 0x2029, 0x202F, 0x205F,
             0x2060, 0x3000, 0xFEFF:
            true
        default:
            false
        }
    }

    private static func validateExistingRendererArtifacts(
        _ artifacts: [ShopOpenEvidenceArtifactV1],
        formulaSafeCSVRows: [[String]]
    ) throws {
        let contentArtifacts = artifacts.filter { $0.format != .manifest }
        guard let pdf = contentArtifacts.first(where: { $0.format == .pdf }),
              let openJSON = contentArtifacts.first(where: { $0.format == .openJSON }),
              let structuredText = contentArtifacts.first(where: { $0.format == .structuredText }),
              let csv = contentArtifacts.first(where: { $0.format == .formulaSafeCSV }),
              contentArtifacts.count == 4,
              try formulaSafeCSV(rows: formulaSafeCSVRows) == csv.bytes else {
            throw ShopReportProfileFailureV1.artifactMismatch
        }
        let projection = try DeterministicOpenJSONRendererV1.reopen(openJSON.bytes)
        guard try DeterministicPDFRendererV1.reopen(pdf.bytes) == projection,
              try DeterministicOpenJSONRendererV1.reopenStructuredText(structuredText.bytes) == projection else {
            throw ShopReportProfileFailureV1.artifactMismatch
        }
    }

    private static func hashManifestArtifact(
        profile: ShopReportProfileV1,
        finalizedBinding: FinalizedReportProfileBindingV1,
        detailReceipt: EvidenceDetailCardRenderReceiptV1,
        confirmation: FinalAudiencePrivacyConfirmationV1,
        contentArtifacts: [ShopOpenEvidenceArtifactV1],
        media: [OutputScopedContentReferenceV1],
        packaging: ShopOpenEvidencePackagingV1,
        accessibleAssessment: AccessibleDocumentAssessmentReceiptV1,
        accessibleOutput: AccessibleDocumentRenderOutputV1
    ) throws -> ShopOpenEvidenceArtifactV1 {
        let manifest = try ShopOpenEvidenceHashManifestV1(
            profile: profile,
            finalizedBinding: finalizedBinding,
            detailReceipt: detailReceipt,
            confirmation: confirmation,
            artifacts: contentArtifacts,
            media: media,
            packaging: packaging,
            accessibleAssessment: accessibleAssessment,
            accessibleOutput: accessibleOutput
        )
        let bytes = try manifest.canonicalData()
        guard try ShopReportProfileCanonicalCodecV1.decode(
            ShopOpenEvidenceHashManifestV1.self,
            from: bytes
        ) == manifest else {
            throw ShopReportProfileFailureV1.artifactMismatch
        }
        return try .init(format: .manifest, bytes: bytes)
    }

    private static func validateHashManifestArtifact(
        profile: ShopReportProfileV1,
        finalizedBinding: FinalizedReportProfileBindingV1,
        detailReceipt: EvidenceDetailCardRenderReceiptV1,
        confirmation: FinalAudiencePrivacyConfirmationV1,
        artifacts: [ShopOpenEvidenceArtifactV1],
        media: [OutputScopedContentReferenceV1],
        packaging: ShopOpenEvidencePackagingV1,
        accessibleAssessment: AccessibleDocumentAssessmentReceiptV1,
        accessibleOutput: AccessibleDocumentRenderOutputV1
    ) throws {
        let contentArtifacts = artifacts.filter { $0.format != .manifest }
        let manifestArtifacts = artifacts.filter { $0.format == .manifest }
        guard artifacts.count == 5,
              manifestArtifacts.count == 1 else {
            throw ShopReportProfileFailureV1.artifactMismatch
        }
        let expected = try hashManifestArtifact(
            profile: profile,
            finalizedBinding: finalizedBinding,
            detailReceipt: detailReceipt,
            confirmation: confirmation,
            contentArtifacts: contentArtifacts,
            media: media,
            packaging: packaging,
            accessibleAssessment: accessibleAssessment,
            accessibleOutput: accessibleOutput
        )
        guard manifestArtifacts[0] == expected else {
            throw ShopReportProfileFailureV1.artifactMismatch
        }
    }

}

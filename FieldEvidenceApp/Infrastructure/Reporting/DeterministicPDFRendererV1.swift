import Foundation
import CryptoKit
import Darwin
#if canImport(CoreImage)
import CoreGraphics
import CoreImage
#endif
#if canImport(CoreText)
import CoreText
#endif

enum GuidedSurveyDeterministicPDFBoundaryV1 {
    static func validate(_ projection: SurveyPublicationReportProjectionV1) throws {
        try projection.validate()
    }
    static let frozenPublicationBytesAreRewritten = false
}

extension DeterministicPDFRendererV1 {
    /// Stable metadata lines for the existing PDF renderer. They intentionally
    /// describe completion/publication identity only, never a survey outcome.
    static func surveyPublicationTextLines(
        _ projection: SurveyPublicationReportProjectionV1
    ) throws -> [String] {
        try projection.validate()
        return [
            "Survey publication: \(projection.snapshotID.uuidString.lowercased())",
            "Session revision: \(projection.sessionRevision)",
            "Recorded facts: \(projection.factCount)",
            "Evidence references: \(projection.evidenceCount)",
        ]
    }
}

// MARK: - C29 plan and rebase PDF metadata

enum PlanReportPDFBoundaryV1 {
    static let localMetadataOnly = true
    static let historicalDisplayIsFrozen = true
    static let previewIsNotApplied = true
    static let excludesSourceBytes = true
    static let excludesPrivateLocators = true
    static let excludesActorIdentity = true
    static let excludesUnsupportedClaims = true

    static func validate(_ projection: PlanReportProjectionV1) throws {
        guard localMetadataOnly, historicalDisplayIsFrozen,
              previewIsNotApplied, excludesSourceBytes,
              excludesPrivateLocators, excludesActorIdentity,
              excludesUnsupportedClaims else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        try PlanReportProjectionPolicyV1.validate(projection, format: .pdf)
    }
}

extension DeterministicPDFRendererV1 {
    /// Stable, localized metadata lines for a versioned plan report. The
    /// normalized coordinates and rebase facts are recorded facts; a preview
    /// remains explicitly unapplied until a separate receipt is recorded.
    static func planTextLines(
        _ projection: PlanReportProjectionV1
    ) throws -> [String] {
        try PlanReportPDFBoundaryV1.validate(projection)
        let labels = PlanReportOpenJSONLabelsV1(projection: projection)
        try labels.validate(projection: projection)

        var lines = [
            labels.heading,
            "\(labels.document): \(projection.documentReference.planDocumentID.uuidString.lowercased())",
            "\(labels.revision): \(projection.revisionReference.planRevisionID.uuidString.lowercased())",
            "\(labels.documentState): \(labels.documentStates[projection.documentState.rawValue] ?? projection.documentState.rawValue)",
            "\(labels.revisionState): \(labels.revisionStates[projection.revisionState.rawValue] ?? projection.revisionState.rawValue)",
            "\(labels.placement): \(projection.placements.count)",
            labels.historyImmutable,
            labels.previewNotApplied,
            labels.claimBoundary,
        ]

        for placement in projection.placements {
            let disposition = labels.placementDispositions[placement.disposition]
                ?? placement.disposition.rawValue
            lines.append(
                "\(labels.placement) \(placement.placementID.uuidString.lowercased()): \(disposition) (\(labels.coordinate) \(placement.xMillionths),\(placement.yMillionths))"
            )
        }

        if let preview = projection.preview {
            lines.append("\(labels.rebasePreview): \(preview.previewID.uuidString.lowercased())")
            lines.append("\(labels.expectedRevision): \(preview.expectedRevision)")
            lines.append("\(labels.rebaseWarning): \(preview.warningCodes.count)")
            lines.append(labels.previewNotApplied)
        }
        if let receipt = projection.receipt {
            let decision = labels.decisions[receipt.decision.rawValue]
                ?? receipt.decision.rawValue
            lines.append("\(labels.rebaseReceipt): \(receipt.receiptID.uuidString.lowercased())")
            lines.append("\(labels.rebaseDecision): \(decision)")
        }
        lines.append(labels.nextStep)

        guard !lines.isEmpty,
              lines.allSatisfy({ !$0.isEmpty }),
              !PlanLocalizationPolicyV1.containsProhibitedClaim(lines) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
        return lines
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Reporting_DeterministicPDFRendererV1 {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

enum DeterministicPDFRendererV1 {
    static let rendererVersion = "deterministic-pdf-renderer-v1"

    private static let inventoryBegin = "%AR-SEMANTIC-BEGIN"
    private static let inventoryRow = "%AR-SEMANTIC-ROW:"
    private static let inventoryEnd = "%AR-SEMANTIC-END"
    private static let inventoryChunkBytes = 57
    static func render(
        _ projection: ReportSemanticProjectionV1,
        layoutProfile: ReportLayoutProfileV1
    ) throws -> ReportProjectionOutputV1 {
        let validated = try projection.recursivelyValidated()
        guard layoutProfile.schemaVersion == ReportLayoutProfileV1.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        let landscape = layoutProfile.orientation == .landscape
        let pageWidth = landscape ? 792 : 612
        let pageHeight = landscape ? 612 : 792
        let maximumVisibleColumns = landscape ? 116 : 88
        let pageLineCount = landscape ? 36 : 48
        let semanticData = try DeterministicOpenJSONRendererV1.render(validated).data
        let sourceLines = [
            "AssetRounds report",
            "Snapshot: \(validated.snapshotID)",
            "Snapshot SHA-256: \(validated.snapshotSHA256)",
            "Profile: \(layoutProfile.profileID) release \(layoutProfile.profileRelease)",
            "Audience/detail: \(layoutProfile.audience.rawValue) / \(layoutProfile.detail.rawValue)",
            "Locale/units: \(layoutProfile.localeIdentifier) / \(layoutProfile.unitsProfileID)",
            "Orientation/media: \(layoutProfile.orientation.rawValue) / \(layoutProfile.mediaLayout.rawValue)",
        ] + validated.nodes.map {
            "[\($0.semanticID)|\($0.sectionID)|\($0.role)] \($0.label): \($0.value)" +
            ($0.outputReferenceID.map { " [\($0)]" } ?? "")
        }
        let lines = sourceLines.flatMap { wrap(asciiVisible($0), columns: maximumVisibleColumns) }
        let pages = stride(from: 0, to: lines.count, by: pageLineCount).map {
            Array(lines[$0..<min($0 + pageLineCount, lines.count)])
        }
        guard !pages.isEmpty, pages.count <= 64 else { throw SnapshotProjectionFailureV1.limitExceeded }

        let catalogID = 1
        let pagesID = 2
        let fontID = 3
        let firstPageID = 4
        var objects: [Int: Data] = [:]
        var pageIDs: [Int] = []
        for index in pages.indices {
            let pageID = firstPageID + index * 2
            let streamID = pageID + 1
            pageIDs.append(pageID)
            let stream = contentStream(pages[index], pageHeight: pageHeight)
            objects[streamID] = Data("<< /Length \(stream.count) >>\nstream\n".utf8) + stream + Data("\nendstream".utf8)
            objects[pageID] = Data("<< /Type /Page /Parent \(pagesID) 0 R /MediaBox [0 0 \(pageWidth) \(pageHeight)] /Resources << /Font << /F1 \(fontID) 0 R >> >> /Contents \(streamID) 0 R >>".utf8)
        }
        objects[catalogID] = Data("<< /Type /Catalog /Pages \(pagesID) 0 R >>".utf8)
        objects[pagesID] = Data("<< /Type /Pages /Count \(pageIDs.count) /Kids [\(pageIDs.map { "\($0) 0 R" }.joined(separator: " "))] >>".utf8)
        objects[fontID] = Data("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".utf8)

        var pdf = Data("%PDF-1.4\n%AssetRounds-V23\n".utf8)
        appendSemanticInventory(semanticData, to: &pdf)
        let objectCount = objects.keys.max() ?? 0
        var offsets = Array(repeating: 0, count: objectCount + 1)
        for objectID in 1...objectCount {
            guard let body = objects[objectID] else { throw SnapshotProjectionFailureV1.missingBinding }
            offsets[objectID] = pdf.count
            pdf.append(Data("\(objectID) 0 obj\n".utf8))
            pdf.append(body)
            pdf.append(Data("\nendobj\n".utf8))
        }
        let xrefOffset = pdf.count
        pdf.append(Data("xref\n0 \(objectCount + 1)\n0000000000 65535 f \n".utf8))
        for objectID in 1...objectCount {
            pdf.append(Data(String(format: "%010d 00000 n \n", offsets[objectID]).utf8))
        }
        pdf.append(Data("trailer\n<< /Size \(objectCount + 1) /Root \(catalogID) 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
        guard pdf.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        guard try reopen(pdf) == validated else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return ReportProjectionOutputV1(
            format: .pdf,
            data: pdf,
            sha256: KernelCanonicalHashV1.sha256(pdf),
            semanticSHA256: projection.semanticSHA256,
            orderedSemanticIDs: projection.nodes.map(\.semanticID),
            taggedPDFAccessibilityEvidence: false
        )
    }

    private static func contentStream(_ lines: [String], pageHeight: Int) -> Data {
        var commands: [String] = []
        for (index, line) in lines.enumerated() {
            let y = pageHeight - 44 - index * 15
            commands.append("BT /F1 9 Tf 42 \(y) Td (\(pdfLiteral(line))) Tj ET")
        }
        return Data(commands.joined(separator: "\n").utf8)
    }

    static func reopen(_ data: Data) throws -> ReportSemanticProjectionV1 {
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              data.starts(with: Data("%PDF-1.4\n".utf8)),
              Data(data.suffix(6)) == Data("%%EOF\n".utf8),
              let source = String(data: data, encoding: .ascii) else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let beginIndex = lines.firstIndex(where: { $0.hasPrefix(inventoryBegin + " ") }),
              let endIndex = lines.firstIndex(of: inventoryEnd), beginIndex < endIndex,
              lines.lastIndex(where: { $0.hasPrefix(inventoryBegin + " ") }) == beginIndex,
              lines.lastIndex(of: inventoryEnd) == endIndex else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        let fields = lines[beginIndex].split(separator: " ")
        guard fields.count == 3, let expectedCount = Int(fields[1]), expectedCount > 0,
              expectedCount <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              KernelCanonicalHashV1.validSHA256(String(fields[2])) else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        let encodedRows = Array(lines[(beginIndex + 1)..<endIndex])
        guard !encodedRows.isEmpty,
              encodedRows.count <= (SnapshotProjectionLimitsV1.maximumProjectionBytes + inventoryChunkBytes - 1) / inventoryChunkBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        var semanticData = Data()
        for (index, row) in encodedRows.enumerated() {
            let expectedPrefix = inventoryRow + String(format: "%06d:", index)
            guard row.hasPrefix(expectedPrefix),
                  let chunk = Data(base64Encoded: String(row.dropFirst(expectedPrefix.count))),
                  !chunk.isEmpty, chunk.count <= inventoryChunkBytes,
                  (index < encodedRows.count - 1 ? chunk.count == inventoryChunkBytes : true) else {
                throw SnapshotProjectionFailureV1.projectionDisagreement
            }
            semanticData.append(chunk)
        }
        guard semanticData.count == expectedCount,
              KernelCanonicalHashV1.sha256(semanticData) == String(fields[2]) else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
        return try DeterministicOpenJSONRendererV1.reopen(semanticData)
    }

    private static func appendSemanticInventory(_ data: Data, to pdf: inout Data) {
        pdf.append(Data("\(inventoryBegin) \(data.count) \(KernelCanonicalHashV1.sha256(data))\n".utf8))
        var index = 0
        var offset = 0
        while offset < data.count {
            let end = min(offset + inventoryChunkBytes, data.count)
            let encoded = Data(data[offset..<end]).base64EncodedString()
            pdf.append(Data("\(inventoryRow)\(String(format: "%06d", index)):\(encoded)\n".utf8))
            offset = end
            index += 1
        }
        pdf.append(Data("\(inventoryEnd)\n".utf8))
    }

    private static func asciiVisible(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            if (0x20...0x7E).contains(scalar.value) {
                return String(scalar)
            }
            return "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
        }.joined()
    }

    private static func wrap(_ value: String, columns: Int) -> [String] {
        guard !value.isEmpty else { return [""] }
        var result: [String] = []
        var remainder = value[...]
        while !remainder.isEmpty {
            let limit = remainder.index(remainder.startIndex, offsetBy: min(columns, remainder.count))
            if limit == remainder.endIndex {
                result.append(String(remainder))
                break
            }
            let candidate = remainder[..<limit]
            let breakIndex = candidate.lastIndex(of: " ").map { remainder.index(after: $0) } ?? limit
            result.append(String(remainder[..<breakIndex]).trimmingCharacters(in: .whitespaces))
            remainder = remainder[breakIndex...].drop(while: { $0 == " " })
        }
        return result
    }

    private static func pdfLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }
}

extension DeterministicPDFRendererV1{
    static func bindAccessibleAssessmentOutput(_ output:ReportProjectionOutputV1,tree:AccessibleDocumentSemanticTreeV1)throws->AccessibleDocumentRenderOutputV1{try tree.validate();guard output.format == .pdf else{throw AccessibleDocumentFailureV1.invalidValue};return try .init(bytes:output.data,mediaType:"application/pdf",rendererID:"deterministic-pdf-renderer",rendererVersion:rendererVersion)}
}

extension DeterministicPDFRendererV1 {
    /// C18's PDF consumer records the same frozen package identity as Open
    /// JSON. This sidecar is canonical metadata only; package bytes and draft
    /// payloads remain outside rendered report output.
    static func packageEvolutionMetadataData(
        _ report: PackageEvolutionReportProjectionV1
    ) throws -> Data {
        try report.validate()
        let data = try PackageEvolutionCanonicalCodecV1.encode(report)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func reopenPackageEvolutionMetadata(
        _ data: Data
    ) throws -> PackageEvolutionReportProjectionV1 {
        let report = try PackageEvolutionCanonicalCodecV1.decode(
            PackageEvolutionReportProjectionV1.self,
            from: data
        )
        try report.validate()
        guard try packageEvolutionMetadataData(report) == data else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return report
    }

    static func validatePackageEvolutionSandbox(
        _ run: PackageSandboxRunV1
    ) throws {
        try PackageEvolutionReportConsumerPolicyV1.validateSandbox(run)
    }

    /// C19 PDF metadata is a deterministic textual companion to the normal
    /// semantic report renderer. It carries exact decimal components and
    /// typed recorded states, while omitting operator, serial, and evidence
    /// locator detail.
    static func measurementIntegrityMetadataData(
        _ projection: MeasurementIntegrityReportProjectionV1
    ) throws -> Data {
        try projection.validate()
        try EvidenceDetailMeasurementIntegrityProjectionGuardV1.validate(projection)
        let envelope = try MeasurementIntegrityOpenJSONEnvelopeV1(projection: projection)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(envelope)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func reopenMeasurementIntegrityMetadata(
        _ data: Data
    ) throws -> MeasurementIntegrityReportProjectionV1 {
        try DeterministicOpenJSONRendererV1.reopenMeasurementIntegrity(data)
    }

    static func measurementIntegrityTextLines(
        _ projection: MeasurementIntegrityReportProjectionV1
    ) throws -> [String] {
        try projection.validate()
        let labels = MeasurementIntegrityOpenJSONLabelsV1(projection: projection)
        try labels.validate()
        let exactValue = "\(projection.canonicalValue.mantissa)e-\(projection.canonicalValue.scale)"
        var lines = [
            labels.heading,
            "\(labels.captureValue): \(exactValue)",
            "\(labels.captureUnit): \(projection.canonicalUnitID)",
            "\(labels.captureSource): \(labels.captureSourceValue)",
        ]
        if let calibration = labels.calibrationStatus {
            lines.append("\(MeasurementIntegrityLocalizationKeyV1.calibrationStatus.englishDefaultValue): \(calibration)")
        }
        if let quality = labels.qualityResult {
            lines.append("\(MeasurementIntegrityLocalizationKeyV1.qualityResult.englishDefaultValue): \(quality)")
        }
        lines.append(labels.nextStep)
        return lines
    }

    /// C20 PDF companions are canonical metadata. They identify only the
    /// approved derivative binding and localized state; bytes and original
    /// content references remain outside this renderer.
    static func privacyTransformMetadataData(
        _ projection: PrivacyTransformReportProjectionV1
    ) throws -> Data {
        try projection.validate()
        try PrivacyTransformReportConsumerPolicyV1.validate(projection, format: .pdf)
        let envelope = try PrivacyTransformOpenJSONEnvelopeV1(projection: projection)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func reopenPrivacyTransformMetadata(
        _ data: Data
    ) throws -> PrivacyTransformReportProjectionV1 {
        try DeterministicOpenJSONRendererV1.reopenPrivacyTransform(data)
    }

    static func privacyTransformTextLines(
        _ projection: PrivacyTransformReportProjectionV1
    ) throws -> [String] {
        try projection.validate()
        try PrivacyTransformReportConsumerPolicyV1.validate(projection, format: .pdf)
        let labels = PrivacyTransformOpenJSONLabelsV1(projection: projection)
        try labels.validate()
        return [
            labels.heading,
            "\(labels.redactionDeclaration): \(projection.redactionDeclared ? "Recorded" : "Not recorded")",
            "\(labels.derivative): \(projection.derivativeContentID)",
            "\(labels.derivativeOnly): \(projection.derivativeOnly ? "Yes" : "No")",
            "\(labels.review): \(labels.reviewState)",
            "\(labels.freshness): \(labels.freshness)",
            "\(labels.projection): \(labels.projectionState)",
            "\(labels.originalAccess): \(labels.originalAccess)",
            labels.nextStep,
        ]
    }
}

// MARK: - C21 client capability and package lifecycle metadata

extension DeterministicPDFRendererV1 {
    /// The C21 PDF companion is metadata-only. It preserves the recorded
    /// admission/lifecycle facts and historic-export disposition without
    /// embedding package payloads or client/device identity.
    static func clientCapabilityMetadataData(
        _ projection: ClientCapabilityReportProjectionV1
    ) throws -> Data {
        try projection.validate()
        try ClientCapabilityReportConsumerPolicyV1.validate(projection, format: .pdf)
        let envelope = try ClientCapabilityOpenJSONEnvelopeV1(projection: projection)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func reopenClientCapabilityMetadata(
        _ data: Data
    ) throws -> ClientCapabilityReportProjectionV1 {
        try DeterministicOpenJSONRendererV1.reopenClientCapability(data)
    }

    static func clientCapabilityTextLines(
        _ projection: ClientCapabilityReportProjectionV1
    ) throws -> [String] {
        try projection.validate()
        try ClientCapabilityReportConsumerPolicyV1.validate(projection, format: .pdf)
        let labels = ClientCapabilityOpenJSONLabelsV1(projection: projection)
        try labels.validate()
        var lines = [
            labels.heading,
            "\(labels.admission): \(labels.admissionState)",
            "\(labels.lifecycle): \(labels.lifecycleState)",
            "\(labels.operation): \(labels.operation)",
            "\(labels.reason): \(labels.reason)",
        ]
        if let historicExport = labels.historicExport {
            lines.append(historicExport)
        }
        if let withdrawal = labels.withdrawal {
            lines.append(withdrawal)
        }
        if let blocked = labels.blocked {
            lines.append(blocked)
        }
        lines.append(labels.nextStep)
        return lines
    }
}

// MARK: - C23 version-bound field-reference metadata

extension DeterministicPDFRendererV1 {
    /// PDF receives the same bounded release/binding projection as Open JSON;
    /// no reference bytes, private locators, or license notices are copied.
    static func fieldReferenceMetadataData(
        _ projection: FieldReferenceReportProjectionV1
    ) throws -> Data {
        try FieldReferenceReportProjectionPolicyV1.validate(projection, format: .pdf)
        let envelope = try FieldReferenceOpenJSONEnvelopeV1(projection: projection)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return data
    }

    static func reopenFieldReferenceMetadata(
        _ data: Data
    ) throws -> FieldReferenceReportProjectionV1 {
        try DeterministicOpenJSONRendererV1.reopenFieldReference(data)
    }

    static func fieldReferenceTextLines(
        _ projection: FieldReferenceReportProjectionV1
    ) throws -> [String] {
        try FieldReferenceReportProjectionPolicyV1.validate(projection, format: .pdf)
        let labels = FieldReferenceOpenJSONLabelsV1(projection: projection)
        try labels.validate()
        return [
            labels.heading,
            "\(labels.kind): \(labels.kindValue)",
            "\(labels.semanticVersion): \(projection.semanticVersion)",
            "\(labels.provenance): \(labels.provenanceValue)",
            "\(labels.licenseScope): \(labels.licenseScopeValue)",
            "\(labels.release): \(labels.releaseValue)",
            "\(labels.binding): \(labels.subjectValue)",
            "\(labels.availability): \(labels.availabilityValue)",
            "\(labels.requiredContent): \(projection.requiredContentCount)",
            "\(labels.missingContent): \(projection.missingContentCount)",
            labels.nextStep,
        ]
    }
}

// MARK: - C25 survey-definition PDF display

extension DeterministicPDFRendererV1 {
    /// Returns deterministic, localized lines for the existing renderer.
    /// Only definition/release metadata is displayed; prompts, answers,
    /// locators, bytes, and actor identity remain outside the projection.
    static func surveyDefinitionTextLines(
        _ projection: SurveyDefinitionReportProjectionV1
    ) throws -> [String] {
        try projection.validate(format: .pdf)
        let kind = BundledLocalizationCatalogV1.localized(
            SurveyDefinitionLocalizationKeyV1.activityKindKey(
                projection.metadata.activityKind
            )
        )
        let lifecycle = BundledLocalizationCatalogV1.localized(
            SurveyDefinitionLocalizationKeyV1.lifecycleKey(
                projection.metadata.lifecycleState
            )
        )
        return [
            BundledLocalizationCatalogV1.localized(.reportHeading),
            "\(BundledLocalizationCatalogV1.localized(.reportDefinition)): \(projection.metadata.definitionID)",
            "\(BundledLocalizationCatalogV1.localized(.reportRelease)): \(projection.metadata.releaseID)",
            "\(BundledLocalizationCatalogV1.localized(.reportActivityKind)): \(kind)",
            "\(BundledLocalizationCatalogV1.localized(.reportLifecycle)): \(lifecycle)",
            "\(BundledLocalizationCatalogV1.localized(.reportSections)): \(projection.sectionIDs.count)",
            "\(BundledLocalizationCatalogV1.localized(.reportFacts)): \(projection.includedFactIDs.count)",
            BundledLocalizationCatalogV1.localized(.reportClaimBoundary),
            BundledLocalizationCatalogV1.localized(.nextStepReviewRecordedFacts),
        ]
    }

    static let surveyDefinitionHistoricOutputIsFrozen = true
    static let surveyDefinitionUsesExistingRenderer = true
}

// MARK: - C28 schedule and occurrence PDF metadata

enum ScheduleReportPDFBoundaryV1 {
    static let localMetadataOnly = true
    static let historicalDisplayUsesRecordedBasis = true
    static let notificationDeliveryIsTruth = false
    static let excludesNotificationPayload = true
    static let excludesActorIdentity = true
    static let excludesWorkInstanceIdentity = true

    static func validate(_ projection: ScheduleReportProjectionV1) throws {
        guard localMetadataOnly, historicalDisplayUsesRecordedBasis,
              !notificationDeliveryIsTruth, excludesNotificationPayload,
              excludesActorIdentity, excludesWorkInstanceIdentity else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        try ScheduleReportProjectionPolicyV1.validate(projection, format: .pdf)
    }
}

extension DeterministicPDFRendererV1 {
    /// Stable, localized metadata lines for a schedule report. Notification
    /// previews are named as previews and never become occurrence evidence.
    static func scheduleTextLines(
        _ projection: ScheduleReportProjectionV1
    ) throws -> [String] {
        try ScheduleReportPDFBoundaryV1.validate(projection)
        let recurrenceKey: ScheduleLocalizationKeyV1 =
            projection.recurrenceKind == "FIXED_CALENDAR"
                ? .fixedCalendar
                : .completionRelative
        let recurrence = BundledLocalizationCatalogV1.localized(recurrenceKey)
        let stateLines = projection.occurrences.map { occurrence in
            let label = BundledLocalizationCatalogV1.scheduleDisplayLabel(
                for: occurrence.state
            )
            return "\(BundledLocalizationCatalogV1.localized(.occurrence)) \(occurrence.occurrenceID.rawValue): \(label)"
        }
        let lines = [
            BundledLocalizationCatalogV1.localized(.heading),
            "\(BundledLocalizationCatalogV1.localized(.definition)): \(projection.scheduleDefinitionID.uuidString.lowercased())",
            "\(BundledLocalizationCatalogV1.localized(.definition)): \(recurrence)",
            "\(BundledLocalizationCatalogV1.localized(.occurrence)): \(projection.occurrences.count)",
            "\(BundledLocalizationCatalogV1.localized(.timeBasis)): \(projection.timeBasis.ianaTimeZoneIdentifier)",
            BundledLocalizationCatalogV1.localized(.historyImmutable),
            "\(BundledLocalizationCatalogV1.localized(.dueQueue)): \(projection.occurrences.count)",
            "\(BundledLocalizationCatalogV1.localized(.reminder)): \(BundledLocalizationCatalogV1.localized(.reminderNotTruth))",
            BundledLocalizationCatalogV1.localized(.claimBoundary),
            BundledLocalizationCatalogV1.localized(.nextStep),
        ] + stateLines
        guard !lines.isEmpty,
              lines.allSatisfy({ !$0.isEmpty }),
              !ScheduleLocalizationPolicyV1.containsProhibitedClaim(lines) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
        return lines
    }
}

// MARK: - C37 reference-framed pose PDF metadata

enum C37PoseReportPDFBoundaryV1 {
    static let localMetadataOnly = true
    static let historyIsFrozen = true
    static let rebasePreviewIsNotApplied = true
    static let excludesSensorStream = true
    static let excludesPrivateLocators = true
    static let excludesUnsupportedClaims = true

    static func validate(_ projection: C37PlacementPoseReportProjectionV1) throws {
        guard localMetadataOnly, historyIsFrozen, rebasePreviewIsNotApplied,
              excludesSensorStream, excludesPrivateLocators,
              excludesUnsupportedClaims else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        try C37PoseReportProjectionPolicyV1.validate(projection)
    }
}

extension DeterministicPDFRendererV1 {
    static func placementPoseTextLines(
        _ projection: C37PlacementPoseReportProjectionV1
    ) throws -> [String] {
        try C37PoseReportPDFBoundaryV1.validate(projection)
        let labels = C37PoseReportOpenJSONLabelsV1()
        try labels.validate()
        let rows = projection.history.map {
            C37PoseQualifiedDisplayRowV1(row: $0, labels: labels)
        }
        let lines = [
            labels.heading,
            "\(labels.current): \(projection.currentTipReferences.count)",
            "\(labels.history): \(projection.history.count)",
            labels.historyFrozen,
            labels.previewNotApplied,
            labels.claimBoundary,
        ] + rows.map { "\($0.eventID.uuidString.lowercased()): \($0.text)" } + [
            labels.nextStep,
        ]
        guard !lines.isEmpty,
              lines.allSatisfy({ !$0.isEmpty }),
              !C37PoseLocalizationPolicyV1.containsProhibitedClaim(lines) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
        return lines
    }

    static func poseTextLines(
        _ projection: C37PlacementPoseReportProjectionV1
    ) throws -> [String] {
        try placementPoseTextLines(projection)
    }
}
// MARK: - C30 operating-context PDF projection

extension DeterministicPDFRendererV1 {
    /// Returns localized, qualified lines for a frozen C30 report section.
    /// The display states that the condition was recorded and keeps a solar
    /// calculation or expected control state visibly separate from it.
    static func operatingContextTextLines(
        _ projection: C30EvidenceContextReportReferenceV1
    ) throws -> [String] {
        try projection.validate()
        try C30OperatingContextLocalizationPolicyV1.validate()
        let condition = C30OperatingContextLocalizationKeyV1.conditionKey(
            projection.observedCondition
        ).englishDefaultValue
        let expected = C30OperatingContextLocalizationKeyV1.expectedControlKey(
            projection.expectedControlState
        ).englishDefaultValue
        var lines = [
            C30OperatingContextLocalizationKeyV1.heading.englishDefaultValue,
            "\(C30OperatingContextLocalizationKeyV1.condition.englishDefaultValue): \(condition)",
            "\(C30OperatingContextLocalizationKeyV1.temporalBasis.englishDefaultValue): recorded",
            "\(C30OperatingContextLocalizationKeyV1.expectedControl.englishDefaultValue): \(expected)",
            C30OperatingContextLocalizationKeyV1.historyFrozen.englishDefaultValue,
            C30OperatingContextLocalizationKeyV1.claimBoundary.englishDefaultValue,
        ]
        if projection.derivedCondition != nil {
            lines.append(C30OperatingContextLocalizationKeyV1.derivedCondition.englishDefaultValue)
        }
        if let pair = projection.pairedObservation {
            lines.append(
                pair.isComparable
                    ? C30OperatingContextLocalizationKeyV1.pairedComparable.englishDefaultValue
                    : C30OperatingContextLocalizationKeyV1.pairedMismatch.englishDefaultValue
            )
            if !pair.mismatchReasons.isEmpty {
                lines.append(C30OperatingContextLocalizationKeyV1.pairedMismatchReason.englishDefaultValue)
            }
        } else {
            lines.append(C30OperatingContextLocalizationKeyV1.pairedNotLinked.englishDefaultValue)
        }
        lines.append(C30OperatingContextLocalizationKeyV1.nextStep.englishDefaultValue)
        guard lines.allSatisfy({ !$0.isEmpty }),
              !C30OperatingContextLocalizationPolicyV1.containsProhibitedClaim(lines) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
        return lines
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Reporting_DeterministicPDFRendererV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift", role: .report)
}

// MARK: - C31 lighting PDF text

extension DeterministicPDFRendererV1 {
    static func lightingLines(
        _ projection: C31LightingReportProjectionV1
    ) throws -> [String] {
        try C31LightingProjectionPolicyV1.validate(projection)
        try C31LightingLocalizationPolicyV1.validate()
        var lines = [
            BundledLocalizationCatalogV1.lightingDisplayLabel(for: .systemHeading),
            BundledLocalizationCatalogV1.lightingDisplayLabel(for: .topology),
            "\(C31LightingLocalizationKeyV1.zones.englishDefaultValue): \(projection.zoneCount)",
            "\(C31LightingLocalizationKeyV1.controlGroups.englishDefaultValue): \(projection.controlGroupCount)",
            "\(C31LightingLocalizationKeyV1.luminaires.englishDefaultValue): \(projection.luminaireCount)",
            C31LightingLocalizationKeyV1.claimBoundary.englishDefaultValue,
            C31LightingLocalizationKeyV1.historyFrozen.englishDefaultValue,
            C31LightingLocalizationKeyV1.manualOffline.englishDefaultValue,
        ]
        lines.append(contentsOf: projection.claimTiers.map {
            BundledLocalizationCatalogV1.lightingClaimLabel(for: $0)
        })
        lines.append(contentsOf: projection.issueDispositions.map {
            BundledLocalizationCatalogV1.lightingIssueLabel(for: $0)
        })
        if !projection.safetyStopReasons.isEmpty {
            lines.append(C31LightingLocalizationKeyV1.safetyStop.englishDefaultValue)
            lines.append(C31LightingLocalizationKeyV1.safetyNextStep.englishDefaultValue)
        }
        guard lines.allSatisfy({ !$0.isEmpty }),
              !C31LightingLocalizationPolicyV1.containsProhibitedClaim(lines) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
        return lines
    }
}

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Reporting_DeterministicPDFRendererV1_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

// MARK: - C45 sole-renderer label projection

enum AssetLabelRenderFailureV1: Error, Equatable, Sendable {
    case nativeQRCodeUnavailable
    case nativeUnicodeTextUnavailable
    case invalidQRCode
    case outputLimitExceeded
    case contentDoesNotFit
    case projectionMismatch
}

struct AssetLabelRenderedQRV1: Equatable, Sendable {
    let canonicalPayload: Data
    let moduleCountIncludingQuietZone: Int
    let monochromeBytes: Data

    func decodeCanonicalPayload() throws -> AssetLabelOpaqueQRPayloadV1 {
        try AssetLabelOpaqueQRPayloadV1(canonicalBytes: canonicalPayload)
    }
}

struct AssetLabelRenderedTextV1: Equatable, Sendable {
    let isolatedLines: [String]
    let pixelWidth: Int
    let pixelHeight: Int
    let grayscaleBytes: Data
    let fontPostScriptName: String
}

struct AssetLabelPDFTextInspectionV1: Equatable, Sendable {
    let isolatedLinesByItem: [[String]]
    let usesType1TextOperators: Bool
}

/// Test/host integration hook for an actually independent decoder. Supplying
/// this hook is evidence about the projected matrix only; static code does not
/// claim a physical scan or native acceptance result.
protocol AssetLabelQRIndependentDecodingV1: Sendable {
    func decode(monochromeBytes: Data, moduleCount: Int) throws -> Data
}

extension DeterministicPDFRendererV1 {
    static let assetLabelRendererID = AssetLabelRendererReleaseCatalogV1.rendererID
    static let assetLabelRendererVersion = AssetLabelRendererReleaseCatalogV1.rendererVersion
    static let assetLabelRendererSHA256 = AssetLabelRendererReleaseCatalogV1.rendererSHA256
    static let assetLabelNativeTextLayoutReleaseID = AssetLabelRendererReleaseCatalogV1.nativeTextLayoutReleaseID
    static let assetLabelQuietZoneModules = 4
    static let assetLabelInterpolationEnabled = false
    static let assetLabelOverlaidLogoEnabled = false
    static let assetLabelPhysicalScanAcceptanceClaimed = false
    static let assetLabelBidiIsolationPrefix = "\u{2068}" // FSI
    static let assetLabelBidiIsolationSuffix = "\u{2069}" // PDI
    static let assetLabelNativeFontPostScriptName = "Helvetica"
    static let assetLabelMaximumSourceToVisibleGraphemeFactor = 4

    /// C45 is an additive projection profile on the existing renderer. It
    /// produces one reconciled PDF/CSV/text result and never publishes bytes,
    /// mutates a locator, or claims that a label was printed or delivered.
    static func renderAssetLabels(
        _ plan: AssetLabelGenerationPlanV1
    ) throws -> LabelProjectionResultV1 {
        try plan.validate()
        guard plan.template.rendererID == assetLabelRendererID,
              plan.template.rendererVersion == assetLabelRendererVersion,
              plan.template.rendererSHA256 == assetLabelRendererSHA256,
              plan.template.rendererRelease.nativeTextLayoutReleaseID == assetLabelNativeTextLayoutReleaseID,
              plan.template.rendererRelease == (try AssetLabelRendererReleaseReferenceV1.current),
              plan.template.qrCorrectionLevel == .medium,
              !plan.template.interpolationEnabled,
              !plan.template.overlaidLogoEnabled else {
            throw AssetLabelContractFailureV1.unsupportedTemplate
        }

        let nativeTextEnvironment = try assetLabelNativeTextEnvironment(for: plan)
        let renderedQRs = try plan.items.map { try renderAssetLabelQR($0.qrPayload) }
        for (item, rendered) in zip(plan.items, renderedQRs) {
            guard try rendered.decodeCanonicalPayload() == item.qrPayload else {
                throw AssetLabelRenderFailureV1.projectionMismatch
            }
        }
        let pdf = try assetLabelPDF(
            plan: plan,
            renderedQRs: renderedQRs,
            nativeTextEnvironment: nativeTextEnvironment
        )
        let csv = try assetLabelFormulaSafeCSV(plan)
        let text = try assetLabelAccessibleStructuredText(plan)
        let artifacts = try [
            LabelProjectedArtifactV1(
                kind: .pdf,
                safeFilename: "asset-labels.pdf",
                mediaType: "application/pdf",
                bytes: pdf,
                itemCount: plan.items.count
            ),
            LabelProjectedArtifactV1(
                kind: .formulaSafeCSV,
                safeFilename: "asset-labels.csv",
                mediaType: "text/csv",
                bytes: csv,
                itemCount: plan.items.count
            ),
            LabelProjectedArtifactV1(
                kind: .structuredText,
                safeFilename: "asset-labels.txt",
                mediaType: "text/plain",
                bytes: text,
                itemCount: plan.items.count
            ),
        ]
        let result = try LabelProjectionResultV1(
            plan: plan,
            artifacts: artifacts,
            nativeTextEnvironment: nativeTextEnvironment
        )
        try result.validate(plan: plan)
        return result
    }

    static func renderAssetLabelQR(
        _ payload: AssetLabelOpaqueQRPayloadV1
    ) throws -> AssetLabelRenderedQRV1 {
        try payload.validate()
        #if canImport(CoreImage)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw AssetLabelRenderFailureV1.nativeQRCodeUnavailable
        }
        filter.setValue(payload.canonicalBytes, forKey: "inputMessage")
        filter.setValue(AssetLabelQRCorrectionLevelV1.medium.rawValue, forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage else {
            throw AssetLabelRenderFailureV1.invalidQRCode
        }
        let extent = image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, width == height, width <= 177 else {
            throw AssetLabelRenderFailureV1.invalidQRCode
        }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        CIContext(options: [.cacheIntermediates: false]).render(
            image,
            toBitmap: &rgba,
            rowBytes: width * 4,
            bounds: extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let quiet = assetLabelQuietZoneModules
        let boundedWidth = width + quiet * 2
        var monochrome = [UInt8](repeating: 255, count: boundedWidth * boundedWidth)
        for row in 0..<height {
            for column in 0..<width {
                let source = (row * width + column) * 4
                let average = (Int(rgba[source]) + Int(rgba[source + 1]) + Int(rgba[source + 2])) / 3
                monochrome[(row + quiet) * boundedWidth + column + quiet] = average < 128 ? 0 : 255
            }
        }
        let quietZoneIsWhite = (0..<boundedWidth).allSatisfy { index in
            monochrome[index] == 255
                && monochrome[(boundedWidth - 1) * boundedWidth + index] == 255
                && monochrome[index * boundedWidth] == 255
                && monochrome[index * boundedWidth + boundedWidth - 1] == 255
        }
        guard quietZoneIsWhite else {
            throw AssetLabelRenderFailureV1.invalidQRCode
        }
        return AssetLabelRenderedQRV1(
            canonicalPayload: payload.canonicalBytes,
            moduleCountIncludingQuietZone: boundedWidth,
            monochromeBytes: Data(monochrome)
        )
        #else
        throw AssetLabelRenderFailureV1.nativeQRCodeUnavailable
        #endif
    }

    static func validateIndependentAssetLabelQRDecode(
        _ rendered: AssetLabelRenderedQRV1,
        decoder: any AssetLabelQRIndependentDecodingV1
    ) throws -> AssetLabelOpaqueQRPayloadV1 {
        let decoded = try decoder.decode(
            monochromeBytes: rendered.monochromeBytes,
            moduleCount: rendered.moduleCountIncludingQuietZone
        )
        let payload = try AssetLabelOpaqueQRPayloadV1(canonicalBytes: decoded)
        guard decoded == rendered.canonicalPayload else {
            throw AssetLabelRenderFailureV1.projectionMismatch
        }
        return payload
    }

    static func assetLabelFormulaSafeCSV(
        _ plan: AssetLabelGenerationPlanV1
    ) throws -> Data {
        try plan.validate()
        let header = assetLabelCSVHeader(for: plan.disclosure).joined(separator: ",")
        let rows = try plan.items.map { item in
            try assetLabelCSVValues(item).map(assetLabelCSVField).joined(separator: ",")
        }
        let bytes = Data(([header] + rows).joined(separator: "\r\n").appending("\r\n").utf8)
        guard bytes.count <= AssetLabelCanonicalCodecV1.maximumCanonicalByteCount else {
            throw AssetLabelRenderFailureV1.outputLimitExceeded
        }
        return bytes
    }

    static func assetLabelAccessibleStructuredText(
        _ plan: AssetLabelGenerationPlanV1
    ) throws -> Data {
        try plan.validate()
        var lines = [
            "ASSETROUNDS-ASSET-LABELS-V1",
            "plan-sha256\t\(plan.planSHA256)",
            "item-count\t\(plan.items.count)",
            "claim-boundary\tGenerated locally; not printed, affixed, delivered, or authorization.",
        ]
        for item in plan.items {
            let spoken = item.shortCode.displayValue.map(String.init).joined(separator: " ")
            lines.append("item\t\(item.orderIndex + 1)\tof\t\(plan.items.count)")
            lines.append("short-code\t\(spoken)")
            lines.append("locator-state\t\(item.locatorState.rawValue)")
            if !disclosedAsset(item).isEmpty { lines.append("asset\t\(disclosedAsset(item))") }
            if !disclosedLocation(item).isEmpty { lines.append("location\t\(disclosedLocation(item))") }
        }
        lines.append("END-ASSETROUNDS-ASSET-LABELS-V1")
        let bytes = Data(lines.joined(separator: "\n").appending("\n").utf8)
        guard bytes.count <= AssetLabelCanonicalCodecV1.maximumCanonicalByteCount else {
            throw AssetLabelRenderFailureV1.outputLimitExceeded
        }
        return bytes
    }

    private static func disclosedAsset(_ item: AssetLabelItemSnapshotV1) -> String {
        item.disclosure == .shortCodeOnly ? "" : item.assetDisplay
    }

    private static func disclosedLocation(_ item: AssetLabelItemSnapshotV1) -> String {
        item.disclosure == .assetLocationAndShortCode ? (item.locationDisplay ?? "") : ""
    }

    private static func assetLabelCSVHeader(
        for disclosure: LabelDisclosureProfileV1
    ) -> [String] {
        switch disclosure {
        case .shortCodeOnly:
            return ["schema_version", "order", "short_code", "qr_payload", "disclosure"]
        case .assetAndShortCode:
            return ["schema_version", "order", "short_code", "qr_payload", "asset_display", "disclosure"]
        case .assetLocationAndShortCode:
            return ["schema_version", "order", "short_code", "qr_payload", "asset_display", "location_display", "disclosure"]
        }
    }

    private static func assetLabelCSVValues(
        _ item: AssetLabelItemSnapshotV1
    ) throws -> [String] {
        try item.validate()
        var values = [
            "1", String(item.orderIndex + 1), item.shortCode.displayValue,
            item.qrPayload.canonicalString,
        ]
        switch item.disclosure {
        case .shortCodeOnly:
            break
        case .assetAndShortCode:
            values.append(try assetLabelSafeDisplay(item.assetDisplay))
        case .assetLocationAndShortCode:
            values.append(try assetLabelSafeDisplay(item.assetDisplay))
            guard let location = item.locationDisplay else {
                throw AssetLabelContractFailureV1.invalidValue
            }
            values.append(try assetLabelSafeDisplay(location))
        }
        values.append(item.disclosure.rawValue)
        return values
    }

    private static func assetLabelCSVField(_ value: String) -> String {
        let guarded: String
        let formulaCandidate = value.drop(while: { $0 == " " || $0 == "\t" })
        if let first = formulaCandidate.unicodeScalars.first,
           "=+-@".unicodeScalars.contains(first) {
            guarded = "'" + value
        } else {
            guarded = value
        }
        return "\"" + guarded.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func assetLabelPDF(
        plan: AssetLabelGenerationPlanV1,
        renderedQRs: [AssetLabelRenderedQRV1],
        nativeTextEnvironment: AssetLabelNativeTextEnvironmentV1
    ) throws -> Data {
        guard renderedQRs.count == plan.items.count else {
            throw AssetLabelRenderFailureV1.projectionMismatch
        }
        let geometry = plan.template.geometry
        // `textBoundMicrometres` is the frozen horizontal disclosure bound.
        // Vertical space is derived solely from the closed disclosure line set;
        // treating the horizontal bound as a height can consume the entire cell
        // and leave no integral module scale for the QR image.
        let textPixelWidth = Int(assetLabelPointsInteger(geometry.textBoundMicrometres))
        let renderedTexts = try plan.items.map {
            try renderAssetLabelText(
                $0,
                pixelWidth: textPixelWidth,
                pixelHeight: assetLabelTextPixelHeight(for: $0.disclosure),
                nativeTextEnvironment: nativeTextEnvironment
            )
        }
        let capacity = geometry.capacity
        let slotCount = plan.startOffset + plan.items.count
        let pageCount = (slotCount + capacity - 1) / capacity
        guard pageCount > 0, pageCount <= 1_000 else {
            throw AssetLabelRenderFailureV1.outputLimitExceeded
        }

        var nextObject = 3
        var pageObjects: [Int] = []
        var objects: [Int: Data] = [:]
        for pageIndex in 0..<pageCount {
            let pageObject = nextObject; nextObject += 1
            let contentObject = nextObject; nextObject += 1
            pageObjects.append(pageObject)
            let itemIndexes = plan.items.indices.filter {
                (plan.startOffset + $0) / capacity == pageIndex
            }
            var imageNames: [(String, Int)] = []
            for itemIndex in itemIndexes {
                let imageObject = nextObject; nextObject += 1
                let name = "Q\(itemIndex)"
                imageNames.append((name, imageObject))
                let qr = renderedQRs[itemIndex]
                var imageBody = Data("<< /Type /XObject /Subtype /Image /Width \(qr.moduleCountIncludingQuietZone) /Height \(qr.moduleCountIncludingQuietZone) /ColorSpace /DeviceGray /BitsPerComponent 8 /Length \(qr.monochromeBytes.count) >>\nstream\n".utf8)
                imageBody.append(qr.monochromeBytes)
                imageBody.append(Data("\nendstream".utf8))
                objects[imageObject] = imageBody
                let textObject = nextObject; nextObject += 1
                let textName = "T\(itemIndex)"
                imageNames.append((textName, textObject))
                let text = renderedTexts[itemIndex]
                var textBody = Data("<< /Type /XObject /Subtype /Image /Width \(text.pixelWidth) /Height \(text.pixelHeight) /ColorSpace /DeviceGray /BitsPerComponent 8 /Length \(text.grayscaleBytes.count) >>\nstream\n".utf8)
                textBody.append(text.grayscaleBytes)
                textBody.append(Data("\nendstream".utf8))
                objects[textObject] = textBody
            }
            let content = try assetLabelPageContent(
                plan: plan,
                pageIndex: pageIndex,
                renderedQRs: renderedQRs,
                renderedTexts: renderedTexts
            )
            objects[contentObject] = Data("<< /Length \(content.count) >>\nstream\n".utf8) + content + Data("\nendstream".utf8)
            let xObjects = imageNames.map { "/\($0.0) \($0.1) 0 R" }.joined(separator: " ")
            objects[pageObject] = Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(assetLabelPoints(geometry.pageWidthMicrometres)) \(assetLabelPoints(geometry.pageHeightMicrometres))] /Resources << /XObject << \(xObjects) >> >> /Contents \(contentObject) 0 R >>".utf8)
        }
        objects[1] = Data("<< /Type /Catalog /Pages 2 0 R >>".utf8)
        objects[2] = Data("<< /Type /Pages /Count \(pageObjects.count) /Kids [\(pageObjects.map { "\($0) 0 R" }.joined(separator: " "))] >>".utf8)

        var pdf = Data("%PDF-1.4\n%AssetRounds-Asset-Labels-V1\n".utf8)
        for rendered in renderedTexts {
            let canonicalLines = try AssetLabelCanonicalCodecV1.encode(rendered.isolatedLines)
            pdf.append(Data("%AR-LABEL-TEXT:\(canonicalLines.base64EncodedString())\n".utf8))
        }
        var offsets = [Int](repeating: 0, count: nextObject)
        for objectID in 1..<nextObject {
            guard let body = objects[objectID] else {
                throw AssetLabelRenderFailureV1.projectionMismatch
            }
            offsets[objectID] = pdf.count
            pdf.append(Data("\(objectID) 0 obj\n".utf8)); pdf.append(body); pdf.append(Data("\nendobj\n".utf8))
        }
        let xref = pdf.count
        pdf.append(Data("xref\n0 \(nextObject)\n0000000000 65535 f \n".utf8))
        for objectID in 1..<nextObject {
            pdf.append(Data(String(format: "%010d 00000 n \n", offsets[objectID]).utf8))
        }
        pdf.append(Data("trailer\n<< /Size \(nextObject) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        guard pdf.count <= AssetLabelCanonicalCodecV1.maximumCanonicalByteCount else {
            throw AssetLabelRenderFailureV1.outputLimitExceeded
        }
        return pdf
    }

    private static func assetLabelPageContent(
        plan: AssetLabelGenerationPlanV1,
        pageIndex: Int,
        renderedQRs: [AssetLabelRenderedQRV1],
        renderedTexts: [AssetLabelRenderedTextV1]
    ) throws -> Data {
        let geometry = plan.template.geometry
        let capacity = geometry.capacity
        var commands: [String] = []
        for itemIndex in plan.items.indices {
            let absoluteSlot = plan.startOffset + itemIndex
            guard absoluteSlot / capacity == pageIndex else { continue }
            let slot = absoluteSlot % capacity
            let row = slot / geometry.columns
            let column = slot % geometry.columns
            let cellX = geometry.originXMicrometres + Int64(column) * (geometry.cellWidthMicrometres + geometry.horizontalGapMicrometres)
            let cellTop = geometry.originYMicrometres + Int64(row) * (geometry.cellHeightMicrometres + geometry.verticalGapMicrometres)
            let pageHeight = Int(assetLabelPointsInteger(geometry.pageHeightMicrometres))
            let cellXPoints = Int(assetLabelPointsInteger(cellX))
            let cellYPoints = pageHeight - Int(assetLabelPointsInteger(cellTop + geometry.cellHeightMicrometres))
            let cellWidth = Int(assetLabelPointsInteger(geometry.cellWidthMicrometres))
            let cellHeight = Int(assetLabelPointsInteger(geometry.cellHeightMicrometres))
            let textWidth = Int(assetLabelPointsInteger(geometry.textBoundMicrometres))
            let textHeight = assetLabelTextPixelHeight(for: plan.items[itemIndex].disclosure)
            let matrixCount = renderedQRs[itemIndex].moduleCountIncludingQuietZone
            let moduleScale = min(cellWidth / matrixCount, (cellHeight - textHeight) / matrixCount)
            guard moduleScale >= 1 else { throw AssetLabelContractFailureV1.unsupportedTemplate }
            let imageSize = moduleScale * matrixCount
            let imageX = cellXPoints + max(0, (cellWidth - imageSize) / 2)
            let imageY = cellYPoints + textHeight
            commands.append("q \(imageSize) 0 0 \(imageSize) \(imageX) \(imageY) cm /Q\(itemIndex) Do Q")
            guard renderedTexts[itemIndex].pixelWidth == textWidth,
                  renderedTexts[itemIndex].pixelHeight == textHeight else {
                throw AssetLabelRenderFailureV1.projectionMismatch
            }
            let textX = cellXPoints + max(0, (cellWidth - textWidth) / 2)
            commands.append("q \(textWidth) 0 0 \(textHeight) \(textX) \(cellYPoints) cm /T\(itemIndex) Do Q")
        }
        return Data(commands.joined(separator: "\n").utf8)
    }

    private static func assetLabelTextPixelHeight(
        for disclosure: LabelDisclosureProfileV1
    ) -> Int {
        switch disclosure {
        case .shortCodeOnly:
            return 18
        case .assetAndShortCode:
            return 20
        case .assetLocationAndShortCode:
            return 30
        }
    }

    static func renderAssetLabelText(
        _ item: AssetLabelItemSnapshotV1,
        pixelWidth: Int,
        pixelHeight: Int
    ) throws -> AssetLabelRenderedTextV1 {
        try renderAssetLabelText(
            item,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            nativeTextEnvironment: nil
        )
    }

    private static func renderAssetLabelText(
        _ item: AssetLabelItemSnapshotV1,
        pixelWidth: Int,
        pixelHeight: Int,
        nativeTextEnvironment: AssetLabelNativeTextEnvironmentV1?
    ) throws -> AssetLabelRenderedTextV1 {
        try item.validate()
        guard pixelWidth >= 24, pixelHeight >= 18,
              pixelWidth <= 4_096, pixelHeight <= 1_024 else {
            throw AssetLabelRenderFailureV1.contentDoesNotFit
        }
        let maximumGraphemes = max(8, min(96, (pixelWidth - 8) / 5))
        let lines = try assetLabelPDFDisclosureLines(
            item,
            maximumGraphemes: maximumGraphemes
        )
        guard lines.count * 10 <= pixelHeight else {
            throw AssetLabelRenderFailureV1.contentDoesNotFit
        }
        let isolated = lines.map {
            assetLabelBidiIsolationPrefix + $0 + assetLabelBidiIsolationSuffix
        }
        #if canImport(CoreText)
        var pixels = [UInt8](repeating: 255, count: pixelWidth * pixelHeight)
        guard let context = CGContext(
            data: &pixels,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: 0
        ) else { throw AssetLabelRenderFailureV1.nativeUnicodeTextUnavailable }
        context.setShouldAntialias(false)
        context.setAllowsAntialiasing(false)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSmoothing(false)
        context.setShouldSubpixelPositionFonts(false)
        context.setAllowsFontSubpixelPositioning(false)
        context.setShouldSubpixelQuantizeFonts(false)
        context.setAllowsFontSubpixelQuantization(false)
        context.textMatrix = .identity
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.setFillColor(gray: 0, alpha: 1)
        let baseFont = CTFontCreateWithName(
            assetLabelNativeFontPostScriptName as CFString,
            7,
            nil
        )
        if let nativeTextEnvironment {
            try nativeTextEnvironment.validate(planSHA256: nativeTextEnvironment.planSHA256)
            guard try assetLabelNativeFontIdentity(baseFont) == nativeTextEnvironment.baseFont else {
                throw AssetLabelRenderFailureV1.nativeUnicodeTextUnavailable
            }
        }
        for (index, value) in isolated.enumerated() {
            let (line, actualFonts) = try assetLabelCoreTextLine(value, baseFont: baseFont)
            if let nativeTextEnvironment,
               !actualFonts.allSatisfy({ nativeTextEnvironment.selectedFonts.contains($0) }) {
                throw AssetLabelRenderFailureV1.nativeUnicodeTextUnavailable
            }
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            guard width <= Double(pixelWidth - 8),
                  ascent + descent <= 10 else {
                throw AssetLabelRenderFailureV1.contentDoesNotFit
            }
            let lineBoxBottom = CGFloat(pixelHeight - (index + 1) * 10)
            let baseline = lineBoxBottom + descent + 1
            guard baseline - descent >= lineBoxBottom + 1,
                  baseline + ascent <= lineBoxBottom + 9 else {
                throw AssetLabelRenderFailureV1.contentDoesNotFit
            }
            context.textPosition = CGPoint(
                x: 4,
                y: baseline
            )
            CTLineDraw(line, context)
        }
        return AssetLabelRenderedTextV1(
            isolatedLines: isolated,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            grayscaleBytes: Data(pixels),
            fontPostScriptName: assetLabelNativeFontPostScriptName
        )
        #else
        throw AssetLabelRenderFailureV1.nativeUnicodeTextUnavailable
        #endif
    }

    static func assetLabelNativeTextEnvironment(
        for plan: AssetLabelGenerationPlanV1
    ) throws -> AssetLabelNativeTextEnvironmentV1 {
        try plan.validate()
        #if canImport(CoreText)
        let baseFont = CTFontCreateWithName(
            assetLabelNativeFontPostScriptName as CFString,
            7,
            nil
        )
        let baseIdentity = try assetLabelNativeFontIdentity(baseFont)
        var identities = Set([baseIdentity])
        let pixelWidth = Int(assetLabelPointsInteger(plan.template.geometry.textBoundMicrometres))
        let maximumGraphemes = max(8, min(96, (pixelWidth - 8) / 5))
        for item in plan.items {
            let lines = try assetLabelPDFDisclosureLines(item, maximumGraphemes: maximumGraphemes)
            for line in lines {
                let isolated = assetLabelBidiIsolationPrefix + line + assetLabelBidiIsolationSuffix
                let (_, actualFonts) = try assetLabelCoreTextLine(isolated, baseFont: baseFont)
                identities.formUnion(actualFonts)
            }
        }
        return try AssetLabelNativeTextEnvironmentV1(
            planSHA256: plan.planSHA256,
            nativeTextLayoutReleaseID: assetLabelNativeTextLayoutReleaseID,
            coreTextVersion: CTGetCoreTextVersion(),
            operatingSystemBuild: try assetLabelOperatingSystemBuild(),
            baseFont: baseIdentity,
            selectedFonts: Array(identities)
        )
        #else
        throw AssetLabelRenderFailureV1.nativeUnicodeTextUnavailable
        #endif
    }

    #if canImport(CoreText)
    private static func assetLabelCoreTextLine(
        _ value: String,
        baseFont: CTFont
    ) throws -> (CTLine, Set<AssetLabelNativeFontIdentityV1>) {
        let range = CFRange(location: 0, length: (value as NSString).length)
        let selected = CTFontCreateForString(baseFont, value as CFString, range)
        let attributed = NSAttributedString(
            string: value,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): selected,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], !runs.isEmpty else {
            throw AssetLabelRenderFailureV1.nativeUnicodeTextUnavailable
        }
        var identities = Set<AssetLabelNativeFontIdentityV1>()
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let font = attributes[kCTFontAttributeName as String] as? CTFont else {
                throw AssetLabelRenderFailureV1.nativeUnicodeTextUnavailable
            }
            identities.insert(try assetLabelNativeFontIdentity(font))
        }
        return (line, identities)
    }

    private static func assetLabelNativeFontIdentity(
        _ font: CTFont
    ) throws -> AssetLabelNativeFontIdentityV1 {
        let postScriptName = CTFontCopyPostScriptName(font) as String
        guard let fontURL = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL,
              fontURL.isFileURL else {
            throw AssetLabelRenderFailureV1.nativeUnicodeTextUnavailable
        }
        let values = try fontURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              let byteCount = values.fileSize,
              byteCount > 0,
              byteCount <= 256 * 1_024 * 1_024 else {
            throw AssetLabelRenderFailureV1.nativeUnicodeTextUnavailable
        }
        let handle = try FileHandle(forReadingFrom: fontURL)
        defer { try? handle.close() }
        var observed = 0
        var hasher = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
            observed += bytes.count
            guard observed <= byteCount else {
                throw AssetLabelRenderFailureV1.nativeUnicodeTextUnavailable
            }
            hasher.update(data: bytes)
        }
        guard observed == byteCount else {
            throw AssetLabelRenderFailureV1.nativeUnicodeTextUnavailable
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return try AssetLabelNativeFontIdentityV1(
            postScriptName: postScriptName,
            fontFileSHA256: digest
        )
    }

    private static func assetLabelOperatingSystemBuild() throws -> String {
        var byteCount = 0
        guard sysctlbyname("kern.osversion", nil, &byteCount, nil, 0) == 0,
              byteCount > 1,
              byteCount <= 256 else {
            throw AssetLabelRenderFailureV1.nativeUnicodeTextUnavailable
        }
        var bytes = [CChar](repeating: 0, count: byteCount)
        guard sysctlbyname("kern.osversion", &bytes, &byteCount, nil, 0) == 0 else {
            throw AssetLabelRenderFailureV1.nativeUnicodeTextUnavailable
        }
        let value = String(cString: bytes)
        guard !value.isEmpty else {
            throw AssetLabelRenderFailureV1.nativeUnicodeTextUnavailable
        }
        return value
    }
    #endif

    static func inspectAssetLabelPDFText(
        _ data: Data
    ) throws -> AssetLabelPDFTextInspectionV1 {
        let marker = Data("%AR-LABEL-TEXT:".utf8)
        let newline = Data("\n".utf8)
        var searchStart = data.startIndex
        var values: [[String]] = []
        while searchStart < data.endIndex,
              let markerRange = data.range(of: marker, in: searchStart..<data.endIndex),
              let lineEnd = data.range(of: newline, in: markerRange.upperBound..<data.endIndex)?.lowerBound {
            guard lineEnd - markerRange.upperBound <= AssetLabelCanonicalCodecV1.maximumCanonicalByteCount,
                  let encoded = String(data: data[markerRange.upperBound..<lineEnd], encoding: .ascii),
                  let decoded = Data(base64Encoded: encoded) else {
                throw AssetLabelRenderFailureV1.projectionMismatch
            }
            let lines = try AssetLabelCanonicalCodecV1.decode([String].self, from: decoded)
            guard !lines.isEmpty,
                  lines.allSatisfy({
                      $0.hasPrefix(assetLabelBidiIsolationPrefix)
                          && $0.hasSuffix(assetLabelBidiIsolationSuffix)
                  }) else { throw AssetLabelRenderFailureV1.projectionMismatch }
            values.append(lines)
            searchStart = lineEnd + 1
        }
        guard !values.isEmpty else { throw AssetLabelRenderFailureV1.projectionMismatch }
        let type1 = data.range(of: Data("/Subtype /Type1".utf8)) != nil
            || data.range(of: Data(" Tf ".utf8)) != nil
        return AssetLabelPDFTextInspectionV1(
            isolatedLinesByItem: values,
            usesType1TextOperators: type1
        )
    }

    private static func assetLabelPDFDisclosureLines(
        _ item: AssetLabelItemSnapshotV1,
        maximumGraphemes: Int
    ) throws -> [String] {
        try item.validate()
        var lines = ["Code: \(item.shortCode.displayValue)"]
        switch item.disclosure {
        case .shortCodeOnly:
            break
        case .assetAndShortCode:
            lines.append("Asset: \(try assetLabelSafeDisplay(item.assetDisplay))")
        case .assetLocationAndShortCode:
            lines.append("Asset: \(try assetLabelSafeDisplay(item.assetDisplay))")
            guard let location = item.locationDisplay else {
                throw AssetLabelContractFailureV1.invalidValue
            }
            lines.append("Location: \(try assetLabelSafeDisplay(location))")
        }
        guard lines.allSatisfy({
            $0.count <= maximumGraphemes * assetLabelMaximumSourceToVisibleGraphemeFactor
        }) else { throw AssetLabelRenderFailureV1.contentDoesNotFit }
        return lines.map { assetLabelTruncated($0, maximumGraphemes: maximumGraphemes) }
    }

    private static func assetLabelSafeDisplay(_ value: String) throws -> String {
        let canonical = value.precomposedStringWithCanonicalMapping
        guard value == canonical,
              !value.unicodeScalars.contains(where: {
                  $0.properties.isBidiControl
                      || $0.value < 0x20
                      || (0x7f...0x9f).contains($0.value)
              }) else { throw AssetLabelContractFailureV1.invalidValue }
        return canonical
    }

    private static func assetLabelTruncated(
        _ value: String,
        maximumGraphemes: Int
    ) -> String {
        guard value.count > maximumGraphemes else { return value }
        let prefixCount = max(1, maximumGraphemes - 3)
        return String(value.prefix(prefixCount)) + "..."
    }

    private static func assetLabelPointsInteger(_ micrometres: Int64) -> Int64 {
        micrometres * 72 / 25_400
    }

    private static func assetLabelPoints(_ micrometres: Int64) -> String {
        let thousandths = micrometres * 72_000 / 25_400
        return "\(thousandths / 1_000).\(String(format: "%03lld", abs(thousandths % 1_000)))"
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Reporting_DeterministicPDFRendererV1_swift {
    static let c47IntegrationRole = "SOLE_PDF_RENDERER"
    static let c47SharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let c47InstallationReceipt = InstallationActivityContractReceiptV1.self
    static let c47PunchReceipt = PunchActivityContractReceiptV1.self
    static let c47NoPlanFallback = NoPlanFallbackV1.self
    static let c47UsesExistingWriterRendererStoreAndPackageInfrastructure = true
    static let c47CreatesSecondRouteOrInspectionAlias = false
    static func c47ActivityLines(_ projection: ActivityContractReportProjectionV2) throws -> [String] {
        try projection.envelope.validateForRead()
        var lines = [projection.envelope.title, projection.envelope.kind.rawValue,
                     projection.envelope.state.rawValue]
        if let completed = projection.completed {
            lines.append(completed.payload.activity.completedAt)
        }
        if let reference = projection.completedSnapshotReference {
            lines += ["source_closeout_sha256=\(reference.sourceCloseoutSHA256)",
                      "target_closeout_sha256=\(reference.targetCloseoutSHA256)"]
        }
        if let closeout = projection.installationCloseout {
            lines += [closeout.completion.rawValue, closeout.asBuiltSnapshotSHA256,
                      "recorded_findings=\(closeout.openFindings.count)", closeout.closeoutSHA256]
            if let limitation = closeout.limitation { lines.append(limitation) }
        }
        if let closeout = projection.punchReviewCloseout {
            lines += [closeout.completion.rawValue, closeout.basisSHA256,
                      closeout.scopeAndTimeLimitation, closeout.closeoutSHA256]
            lines += closeout.scope.map {
                "\($0.scopeItemID)|\($0.disposition.rawValue)|findings=\($0.findingLinks.count)"
            }
        }
        return lines
    }
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

enum C47ActivityContractConformance_FieldEvidenceApp_Infrastructure_Reporting_DeterministicPDFRendererV1_swift {
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let noPlanFallback = NoPlanFallbackV1.self
    static let usesExistingInfrastructureOnly = true
    static let createsSecondWriterRendererStoreRouteOrInspectionAlias = false
}

// MARK: - C48 portable-review derived PDF boundary

extension DeterministicPDFRendererV1 {
    /// PDF generation remains owned by the existing deterministic renderer;
    /// only the already-derived history metadata may be validated here.
    static func validatePortableReviewDerivedHistory(
        _ projection: C48PortableReviewDerivedHistoryProjectionV1
    ) throws -> C48PortableReviewDerivedHistoryProjectionV1 {
        try C48PortableReviewReportProjectionBoundaryV1.validate(projection)
        return projection
    }
}

enum C48PortableReviewPDFBoundaryV1 {
    static let usesExistingPDFRenderer = true
    static let emitsDerivedMetadataOnly = true
    static let capabilityBytesEmitted = false
    static let capabilityProofBytesEmitted = false
    static let responseBodyEmitted = false
    static let rawRequestResponseBytesEmitted = false
    static let workspaceAndReplicaIdentityEmitted = false
}

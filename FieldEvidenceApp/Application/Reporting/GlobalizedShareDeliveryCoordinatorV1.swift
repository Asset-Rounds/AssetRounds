import Foundation

struct GlobalizedReportSharePresentationV1: Equatable, Sendable {
    let subject: String
    let body: String
    let documentLanguage: String
}

struct GlobalizedLabelSharePresentationV1: Equatable, Sendable {
    let title: String
    let status: String
    let documentLanguage: String
    let warning: String?
    let claimBoundary: String
}

/// Builds metadata for the existing handoff routes. It has no sender, renderer,
/// persistence, transport, or authority to claim a platform outcome.
enum GlobalizedShareDeliveryCoordinatorV1 {
    static func report(
        _ delivery: ReportDeliveryValue,
        surfaces: GlobalizedSharePrintLabelSurfacesV1 = .init()
    ) -> GlobalizedReportSharePresentationV1 {
        let language = surfaces.documentLanguage(delivery.documentLanguage)
        return .init(subject: surfaces.reportSubject(title: delivery.title),
                     body: surfaces.reportBody(title: delivery.title, subtitle: delivery.subtitle, documentLanguage: language),
                     documentLanguage: language)
    }

    /// Called only after the existing delivery path validated the PDF's exact
    /// stored digest and source snapshot. Legacy bytes remain unclassified.
    static func recordedDocumentLanguage(
        pdf: Data, snapshot: ReportSnapshotV1
    ) throws -> ReportLanguageSelectionV1? {
        guard let metadata = try GlobalizedAccessibleDocumentRendererV1.readEmbeddedMetadataIfPresent(from: pdf) else {
            return nil
        }
        let source = try ReportSnapshotEncoderV1().encode(snapshot)
        let milliseconds = (snapshot.snapshotCreatedAt.timeIntervalSince1970 * 1_000).rounded()
        guard milliseconds.isFinite, milliseconds >= Double(Int64.min), milliseconds < Double(Int64.max),
              metadata.sourceSHA256 == source.sha256,
              metadata.sourceCreatedAtMilliseconds == Int64(milliseconds) else {
            throw ReportDeliveryCoordinatorError.invalidAuthority
        }
        return metadata.language
    }

    static func labels(
        _ export: AssetLabelPreparedExportV1,
        surfaces: GlobalizedSharePrintLabelSurfacesV1 = .init()
    ) -> GlobalizedLabelSharePresentationV1 {
        let key: AssetLabelLocalizationKeyV1
        switch export.reprintEligibility {
        case .activeExactReprint: key = .activeExactReprint
        case .historicExportOnly: key = .historicExportOnly
        case .blockedMissingRelease: key = .blockedMissingRelease
        }
        return .init(title: surfaces.label(.preview), status: surfaces.label(key),
                     documentLanguage: surfaces.documentLanguage(export.documentLanguage),
                     warning: export.requiresDoNotDeployWarning ? surfaces.doNotDeploy : nil,
                     claimBoundary: surfaces.label(.claimBoundary))
    }
}

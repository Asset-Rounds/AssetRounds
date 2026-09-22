import Foundation

/// Reads the existing canonical catalog references and saved artifacts. No
/// second archive/store/writer and no fallback to an active language slot.
enum GlobalizedCatalogReplayAdapterV1 {
    static func catalog(ownerID: String, digest: String,
                        resources: GlobalizedReplayResourcesV1) throws -> GlobalizedCatalogReplayReferenceV1 {
        try resources.validate()
        guard !ownerID.isEmpty, KernelCanonicalHashV1.validSHA256(digest) else {
            throw GlobalizedCatalogReplayFailureV1.invalidSource
        }
        let matching = resources.catalogs.filter {
            $0.descriptor.legacyRelease.releaseSHA256 == digest
        }.sorted { $0.descriptor.releaseID.digest < $1.descriptor.releaseID.digest }
        guard !matching.isEmpty else {
            return .init(ownerID: ownerID, legacyReleaseSHA256: digest,
                         resolvedReleaseID: nil, limitation: .historicalCatalogUnavailable)
        }
        let store = try LocalizationCatalogReleaseStoreV1(archives: resources.catalogs)
        for candidate in matching {
            do {
                let exact = try store.historical(releaseID: candidate.descriptor.releaseID,
                                                 readerVersion: resources.readerVersion)
                guard exact.descriptor.legacyRelease.releaseSHA256 == digest else {
                    throw GlobalizedCatalogReplayFailureV1.invalidResources
                }
                return .init(ownerID: ownerID, legacyReleaseSHA256: digest,
                             resolvedReleaseID: exact.descriptor.releaseID, limitation: nil)
            } catch V30CatalogReleaseContractFailureV1.incompatibleReader { continue }
        }
        return .init(ownerID: ownerID, legacyReleaseSHA256: digest,
                     resolvedReleaseID: nil, limitation: .historicalCatalogReaderIncompatible)
    }

    static func artifact(reportID: UUID, source: Data, sourceSHA256: String,
                         createdAt: Date, pdf: Data, outputSHA256: String,
                         resources: GlobalizedReplayResourcesV1 = .init()) throws -> GlobalizedArtifactReplayObservationV1 {
        try resources.validate()
        guard !source.isEmpty, !pdf.isEmpty,
              KernelCanonicalHashV1.sha256(source) == sourceSHA256,
              KernelCanonicalHashV1.sha256(pdf) == outputSHA256 else {
            throw GlobalizedCatalogReplayFailureV1.artifactMismatch
        }
        let metadata = try GlobalizedAccessibleDocumentRendererV1.readEmbeddedMetadataIfPresent(from: pdf)
        var limitations: [GlobalizedReplayLimitationV1] = []
        if let metadata {
            let milliseconds = (createdAt.timeIntervalSince1970 * 1_000).rounded()
            guard milliseconds.isFinite, milliseconds >= Double(Int64.min),
                  milliseconds < Double(Int64.max) else {
                throw GlobalizedCatalogReplayFailureV1.artifactMismatch
            }
            // Existing clone/fork restore can rebind assurance/temporal source
            // snapshots while preserving the historical PDF. Keep both actual
            // hashes, but never claim that the rebound source reproduces it.
            if metadata.sourceSHA256 != sourceSHA256
                || metadata.sourceCreatedAtMilliseconds != Int64(milliseconds) {
                limitations.append(.historicalSourceBindingUnavailable)
            }
            if !metadata.fonts.allSatisfy({ resources.fonts.contains($0) }) {
                limitations.append(.historicalFontUnavailable)
            }
            if metadata.rendererID != resources.rendererID
                || metadata.rendererVersion != resources.rendererVersion
                || metadata.operatingSystemBuild != resources.operatingSystemBuild {
                limitations.append(.rendererEnvironmentUnavailable)
            }
            // C04 did not embed a catalog release ID. Do not invent one from
            // the current bundle or from a document's language tag.
            limitations.append(.documentCatalogReferenceNotRecorded)
        } else { limitations.append(.legacyArtifactHasNoReplayProvenance) }
        limitations.append(.regenerationNotVerified)
        return .init(reportID: reportID, sourceSHA256: sourceSHA256,
                     outputSHA256: outputSHA256, outputByteCount: pdf.count,
                     metadata: metadata, limitations: limitations)
    }

    static func inventory(records: V4BackupRecordsV1, recordsSHA256: String,
                          resources: GlobalizedReplayResourcesV1 = .init(),
                          readMember: (String) throws -> Data?) throws -> GlobalizedCatalogReplayInventoryV1 {
        try resources.validate()
        guard KernelCanonicalHashV1.validSHA256(recordsSHA256) else {
            throw GlobalizedCatalogReplayFailureV1.invalidSource
        }
        var catalogs: [GlobalizedCatalogReplayReferenceV1] = []
        for row in records.surveyDefinitions where row.kind == .release {
            let release = try SurveyDefinitionCanonicalCodecV1.decode(SurveyDefinitionReleaseV1.self, from: row.canonicalData)
            catalogs.append(try catalog(ownerID: "survey:\(row.id.uuidString.lowercased())",
                                        digest: release.localizationReleaseSHA256, resources: resources))
        }
        for row in records.packageEvolution where row.kind == .promotionReceipt {
            let receipt = try PackageEvolutionCanonicalCodecV1.decode(PackagePromotionReceiptV1.self, from: row.canonicalData)
            for (side, graph) in [("source", receipt.semanticDiff.source), ("target", receipt.semanticDiff.target)] {
                if let digest = graph.semanticReleaseBindings.localizationReleaseSHA256 {
                    catalogs.append(try catalog(ownerID: "promotion:\(row.id.uuidString.lowercased()):\(side)",
                                                digest: digest, resources: resources))
                }
            }
        }
        var artifacts: [GlobalizedArtifactReplayObservationV1] = []
        var pending: [UUID] = []
        for report in records.reports.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let source = try readMember(report.snapshotRelativePath),
                  KernelCanonicalHashV1.sha256(source) == report.snapshotSHA256 else {
                throw GlobalizedCatalogReplayFailureV1.artifactMismatch
            }
            if report.pdfState == ReportPDFState.ready.rawValue {
                guard let path = report.pdfRelativePath, let hash = report.pdfSHA256,
                      let pdf = try readMember(path) else { throw GlobalizedCatalogReplayFailureV1.artifactMismatch }
                let sourceDate: Date
                if report.snapshotSchemaVersion == CompletedActivitySnapshotV2.schemaVersion {
                    let snapshot = try CompletedActivitySnapshotCanonicalCodecV2.decode(source)
                    guard let generatedAt = SnapshotProjectionValidationV1.instantDate(snapshot.payload.activity.generatedAt) else {
                        throw GlobalizedCatalogReplayFailureV1.invalidSource
                    }
                    sourceDate = generatedAt
                } else {
                    sourceDate = try ReportSnapshotEncoderV1().decode(source).snapshotCreatedAt
                }
                artifacts.append(try artifact(reportID: report.id, source: source,
                    sourceSHA256: report.snapshotSHA256, createdAt: sourceDate,
                    pdf: pdf, outputSHA256: hash, resources: resources))
            } else { pending.append(report.id) }
        }
        return .init(recordsSHA256: recordsSHA256,
                     catalogs: catalogs.sorted { $0.ownerID < $1.ownerID },
                     artifacts: artifacts, unrenderedReportIDs: pending)
    }
}

extension ValidatedV4BackupPackageV1 {
    func globalizationReplay(resources: GlobalizedReplayResourcesV1 = .init()) throws -> GlobalizedCatalogReplayInventoryV1 {
        guard let recordsHash = manifest.entries.first(where: { $0.path == "records.json" })?.sha256 else {
            throw GlobalizedCatalogReplayFailureV1.invalidSource
        }
        return try GlobalizedCatalogReplayAdapterV1.inventory(
            records: records, recordsSHA256: recordsHash, resources: resources,
            readMember: { members[$0] })
    }
}

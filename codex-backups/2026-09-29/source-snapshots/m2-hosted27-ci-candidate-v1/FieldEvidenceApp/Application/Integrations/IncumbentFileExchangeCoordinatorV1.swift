import Foundation

/// Pure C50 coordination. It can detect, parse, preview and render, but it owns
/// no workspace writer and cannot turn a preview into canonical application data.
struct IncumbentFileExchangeCoordinatorV1: Sendable {
    private let registry: ClosedIncumbentAdapterRegistryV1
    private let adapters: [any IncumbentFileAdapterV1]

    init(registry: ClosedIncumbentAdapterRegistryV1,
         adapters: [any IncumbentFileAdapterV1]) throws {
        guard adapters.count <= 1,
              Set(adapters.map { $0.adapterID }).count == adapters.count else {
            throw IncumbentFileContractFailureV1.multipleSelectedProfiles
        }
        if let selected = registry.currentProductionReleases.first {
            guard adapters.count == 1, adapters[0].adapterID == selected.adapterID,
                  adapters[0].release == selected else {
                throw IncumbentFileContractFailureV1.staleSelection
            }
        } else if !adapters.isEmpty {
            throw IncumbentFileContractFailureV1.noSelectedProfile
        }
        self.registry = registry; self.adapters = adapters
    }

    func preview(input: IncumbentFileInputV1, scope: IncumbentExchangeScopeV1,
                 at date: Date) throws -> (rows: [IncumbentFileRowV1], preview: IncumbentMappingPreviewV1) {
        let release = try registry.selectedRelease(at: date)
        try scope.validate(release: release)
        guard release.direction.permitsImport, UInt64(input.bytes.count) <= release.budget.maximumByteCount,
              release.filenameExtensions.contains(input.filenameExtension),
              release.uniformTypeIdentifiers.contains(input.uniformTypeIdentifier),
              let adapter = adapters.first, adapter.release == release,
              scope.releaseID == release.releaseID, scope.releaseSHA256 == release.releaseSHA256 else {
            throw IncumbentFileContractFailureV1.unsupportedVersion
        }
        _ = try IncumbentDelimitedTextSafetyV1.validateInputBytes(input.bytes, release: release)
        let detection = try adapter.detect(input)
        let repeatedDetection = try adapter.detect(input)
        guard detection == repeatedDetection else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
        try detection.validate(input: input, release: release)
        let rows = try adapter.parse(input, detection: detection)
        let repeatedRows = try adapter.parse(input, detection: detection)
        guard rows == repeatedRows else { throw IncumbentFileContractFailureV1.invalidDigest }
        try rows.forEach { try $0.validate(release: release) }
        guard rows.count == detection.rowCount, rows.count <= release.budget.maximumRowCount,
              rows.enumerated().allSatisfy({ $0.element.ordinal == $0.offset + 1 }) else {
            throw IncumbentFileContractFailureV1.budgetExceeded
        }
        let preview = try IncumbentMappingPreviewV1(scope: scope, inputSHA256: input.byteSHA256,
            release: release, rowCount: rows.count)
        return (rows, preview)
    }

    func render(projections: [IncumbentAdapterProjectionV1], scope: IncumbentExchangeScopeV1,
                at date: Date) throws -> (data: Data, manifest: IncumbentFileExportManifestV1) {
        let release = try registry.selectedRelease(at: date)
        try scope.validate(release: release)
        guard release.direction.permitsExport, let adapter = adapters.first,
              adapter.release == release, scope.releaseID == release.releaseID,
              scope.releaseSHA256 == release.releaseSHA256 else {
            throw IncumbentFileContractFailureV1.noSelectedProfile
        }
        // One scope carries one exact projection approval. Multiple rows would require
        // independently bound scopes rather than reusing one authority token.
        guard projections.count == 1, let projection = projections.first else {
            throw IncumbentFileContractFailureV1.budgetExceeded
        }
        try projection.validate(scope: scope)
        let row = try IncumbentFileRowV1(
            ordinal: 1, projection: projection, release: release, scope: scope
        )
        let rows = [row]
        return try render(rows: rows, scope: scope, at: date)
    }

    private func render(rows: [IncumbentFileRowV1], scope: IncumbentExchangeScopeV1,
                        at date: Date) throws
        -> (data: Data, manifest: IncumbentFileExportManifestV1) {
        let release = try registry.selectedRelease(at: date)
        try scope.validate(release: release)
        guard release.direction.permitsExport, let adapter = adapters.first,
              adapter.release == release else {
            throw IncumbentFileContractFailureV1.noSelectedProfile
        }
        return try render(rows: rows, scope: scope, release: release, adapter: adapter)
    }

    /// Raw rows are an adapter implementation detail. External export callers must
    /// enter through the exact privacy-bound projection path above.
    private func render(rows: [IncumbentFileRowV1], scope: IncumbentExchangeScopeV1,
                        release: IncumbentFileProfileReleaseV1,
                        adapter: any IncumbentFileAdapterV1) throws
        -> (data: Data, manifest: IncumbentFileExportManifestV1) {
        try rows.forEach { try $0.validate(release: release) }
        let first = try adapter.render(rows: rows, scope: scope)
        let second = try adapter.render(rows: rows, scope: scope)
        guard first == second else { throw IncumbentFileContractFailureV1.invalidDigest }
        try IncumbentDelimitedTextSafetyV1.validateRenderedBytes(
            first, release: release, expectedDataRows: rows.count
        )
        return (first, try IncumbentFileExportManifestV1(
            scope: scope, release: release, output: first, rowCount: rows.count))
    }

    func recover(plan: IncumbentExchangeRecoveryPlanV1, observedSourceSHA256: String,
                 canonicalMutation: IncumbentCanonicalMutationReceiptReferenceV1?,
                 cleanup: IncumbentCleanupEvidenceV1?) throws
        -> IncumbentExchangeRecoveryReceiptV1 {
        try plan.validate(); try IncumbentFileContractV1.requireDigest(observedSourceSHA256)
        guard observedSourceSHA256 == plan.sourceSHA256 else {
            return try IncumbentExchangeRecoveryReceiptV1(plan: plan,
                observedSourceSHA256: observedSourceSHA256, observedReceiptSHA256: nil,
                cleanupEvidenceSHA256: nil, disposition: .divergentQuarantined)
        }
        if let canonicalMutation {
            do {
                try canonicalMutation.validate(plan: plan)
            } catch {
                return try IncumbentExchangeRecoveryReceiptV1(plan: plan,
                    observedSourceSHA256: observedSourceSHA256,
                    observedReceiptSHA256: canonicalMutation.receiptSHA256,
                    cleanupEvidenceSHA256: nil, disposition: .divergentQuarantined)
            }
            if let cleanup {
                do { try cleanup.validate(plan: plan) } catch {
                    return try IncumbentExchangeRecoveryReceiptV1(plan: plan,
                        observedSourceSHA256: observedSourceSHA256,
                        observedReceiptSHA256: canonicalMutation.receiptSHA256,
                        cleanupEvidenceSHA256: cleanup.evidenceSHA256,
                        disposition: .divergentQuarantined)
                }
                return try IncumbentExchangeRecoveryReceiptV1(plan: plan,
                    observedSourceSHA256: observedSourceSHA256,
                    observedReceiptSHA256: canonicalMutation.receiptSHA256,
                    cleanupEvidenceSHA256: cleanup.evidenceSHA256, disposition: .cleanupOnly)
            }
            return try IncumbentExchangeRecoveryReceiptV1(plan: plan,
                observedSourceSHA256: observedSourceSHA256,
                observedReceiptSHA256: canonicalMutation.receiptSHA256,
                cleanupEvidenceSHA256: nil, disposition: .appliedMatchingReceipt)
        }
        if let cleanup {
            return try IncumbentExchangeRecoveryReceiptV1(plan: plan,
                observedSourceSHA256: observedSourceSHA256, observedReceiptSHA256: nil,
                cleanupEvidenceSHA256: cleanup.evidenceSHA256,
                disposition: .divergentQuarantined)
        }
        return try IncumbentExchangeRecoveryReceiptV1(plan: plan,
            observedSourceSHA256: observedSourceSHA256, observedReceiptSHA256: nil,
            cleanupEvidenceSHA256: nil, disposition: .beforeCanonicalEffect)
    }
}

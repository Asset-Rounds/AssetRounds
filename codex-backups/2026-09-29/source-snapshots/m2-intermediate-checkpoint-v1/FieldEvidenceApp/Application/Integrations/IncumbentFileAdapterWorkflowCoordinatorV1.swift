import Foundation

enum IncumbentFileAdapterWorkflowFailureV1: Error, Equatable, Sendable {
    case disabledNoSelectedProfile
    case exactReleaseRequired
    case importBulkUnavailable
    case mismatchedPreview
}

enum IncumbentFileAdapterWorkflowStateV1: String, Codable, CaseIterable, Sendable {
    case disabledNoSelectedProfile = "DISABLED_NO_SELECTED_PROFILE"
    case enabledExactProductionProfile = "ENABLED_EXACT_PRODUCTION_PROFILE"
}

struct IncumbentFileAdapterWorkflowContextV1: Equatable, Sendable {
    let evaluatedAt: Date

    init(evaluatedAt: Date) throws {
        guard evaluatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        self.evaluatedAt = evaluatedAt
    }
}

struct IncumbentFileAdapterWorkflowProjectionV1: Equatable, Sendable {
    let state: IncumbentFileAdapterWorkflowStateV1
    let selectedReleaseID: UUID?
    let selectedReleaseSHA256: String?
    let providerDisplayToken: String?
    let canDetectParseOrMap: Bool
    let canPreviewCanonicalImport: Bool
    let canCommitCanonicalImport: Bool
    let canExport: Bool
    let previewWritesCanonicalState: Bool
    let fileCreatedMeansSynced: Bool
    let fileCreatedMeansDelivered: Bool
    let fileCreatedMeansAccepted: Bool
    let previewMeansImported: Bool
}

struct IncumbentFileAdapterInboundPreviewV1: Equatable, Sendable {
    let rows: [IncumbentFileRowV1]
    let mapping: IncumbentMappingPreviewV1
    let scope: IncumbentExchangeScopeV1
    let releaseID: UUID
    let releaseSHA256: String
    let isZeroWrite: Bool
}

struct IncumbentFileAdapterC08PreviewCommandV1: Sendable {
    let inbound: IncumbentFileAdapterInboundPreviewV1
    let importPlan: ImportPlanV1
    let bulkPlan: BulkCommandPlanV1
    let currentSourceSHA256: String
    let currentWorkspaceRevisionSHA256: String
}

struct IncumbentFileAdapterC08BeginCommandV1: Sendable {
    let sessionID: UUID
    let reentry: IncumbentFileAdapterC08ReentryV1
    let currentSourceSHA256: String
    let currentWorkspaceRevisionSHA256: String
}

struct IncumbentFileAdapterC08CommitCommandV1: Sendable {
    let reentry: IncumbentFileAdapterC08ReentryV1
    let session: BulkSessionV1
    let currentSourceSHA256: String
    let currentWorkspaceRevisionSHA256: String
    let cancellationRequested: Bool
}

struct IncumbentFileAdapterC08ReentryV1: Equatable, Sendable {
    let inbound: IncumbentFileAdapterInboundPreviewV1
    let preview: ImportBulkPreviewV1

    init(
        inbound: IncumbentFileAdapterInboundPreviewV1,
        preview: ImportBulkPreviewV1
    ) throws {
        try preview.importPlan.validate()
        try preview.bulkPlan.validate(importPlan: preview.importPlan)
        guard preview.importPlan.workspaceID == inbound.scope.workspaceID,
              preview.importPlan.source.sourceSHA256 == inbound.mapping.inputSHA256,
              preview.importPlan.mappingProfileSHA256 == inbound.mapping.mappingManifestSHA256 else {
            throw IncumbentFileAdapterWorkflowFailureV1.mismatchedPreview
        }
        self.inbound = inbound
        self.preview = preview
    }
}

enum IncumbentFileAdapterWorkflowCommandV1: Sendable {
    case previewInbound(
        input: IncumbentFileInputV1,
        scope: IncumbentExchangeScopeV1,
        at: Date
    )
    case previewCanonicalImport(IncumbentFileAdapterC08PreviewCommandV1)
    case beginCanonicalImport(IncumbentFileAdapterC08BeginCommandV1)
    case commitOrCancelCanonicalImport(IncumbentFileAdapterC08CommitCommandV1)
    case export(
        projections: [IncumbentAdapterProjectionV1],
        scope: IncumbentExchangeScopeV1,
        at: Date
    )
    case recover(
        scope: IncumbentExchangeScopeV1,
        at: Date,
        plan: IncumbentExchangeRecoveryPlanV1,
        observedSourceSHA256: String,
        canonicalMutation: IncumbentCanonicalMutationReceiptReferenceV1?,
        cleanup: IncumbentCleanupEvidenceV1?
    )
}

enum IncumbentFileAdapterWorkflowOutcomeV1: Sendable {
    case inboundPreview(IncumbentFileAdapterInboundPreviewV1)
    case canonicalPreview(IncumbentFileAdapterC08ReentryV1)
    case canonicalSession(BulkSessionV1)
    case exported(data: Data, manifest: IncumbentFileExportManifestV1)
    case recovered(IncumbentExchangeRecoveryReceiptV1)
}

enum IncumbentFileAdapterWorkflowClaimsV1 {
    static let selectedProductionProfileCount = 0
    static let createsGenericMapper = false
    static let createsCanonicalWriter = false
    static let fileCreatedMeansSynced = false
    static let fileCreatedMeansAccepted = false
    static let fileCreatedMeansDelivered = false
    static let previewMeansImported = false
    static let establishesProviderSuccess = false
}

@MainActor
final class IncumbentFileAdapterWorkflowCoordinatorV1 {
    private let registry: ClosedIncumbentAdapterRegistryV1
    private let exchange: IncumbentFileExchangeCoordinatorV1
    private let importBulk: ImportBulkCoordinatorV1?

    init(
        registry: ClosedIncumbentAdapterRegistryV1,
        exchange: IncumbentFileExchangeCoordinatorV1,
        importBulk: ImportBulkCoordinatorV1? = nil
    ) {
        self.registry = registry
        self.exchange = exchange
        self.importBulk = importBulk
    }

    func projection(
        context: IncumbentFileAdapterWorkflowContextV1
    ) throws -> IncumbentFileAdapterWorkflowProjectionV1 {
        guard let release = registry.currentProductionReleases.first else {
            return IncumbentFileAdapterWorkflowProjectionV1(
                state: .disabledNoSelectedProfile,
                selectedReleaseID: nil,
                selectedReleaseSHA256: nil,
                providerDisplayToken: nil,
                canDetectParseOrMap: false,
                canPreviewCanonicalImport: false,
                canCommitCanonicalImport: false,
                canExport: false,
                previewWritesCanonicalState: false,
                fileCreatedMeansSynced: false,
                fileCreatedMeansDelivered: false,
                fileCreatedMeansAccepted: false,
                previewMeansImported: false
            )
        }
        let selected = try registry.selectedRelease(at: context.evaluatedAt)
        guard selected == release else { throw IncumbentFileAdapterWorkflowFailureV1.exactReleaseRequired }
        return IncumbentFileAdapterWorkflowProjectionV1(
            state: .enabledExactProductionProfile,
            selectedReleaseID: release.releaseID,
            selectedReleaseSHA256: release.releaseSHA256,
            providerDisplayToken: release.providerDisplayToken,
            canDetectParseOrMap: release.direction.permitsImport,
            canPreviewCanonicalImport: release.direction.permitsImport && importBulk != nil,
            canCommitCanonicalImport: release.direction.permitsImport && importBulk != nil,
            canExport: release.direction.permitsExport,
            previewWritesCanonicalState: false,
            fileCreatedMeansSynced: false,
            fileCreatedMeansDelivered: false,
            fileCreatedMeansAccepted: false,
            previewMeansImported: false
        )
    }

    func execute(
        _ command: IncumbentFileAdapterWorkflowCommandV1
    ) throws -> IncumbentFileAdapterWorkflowOutcomeV1 {
        switch command {
        case let .previewInbound(input, scope, date):
            let release = try requireRelease(scope: scope, at: date)
            let result = try exchange.preview(input: input, scope: scope, at: date)
            try result.preview.validate(scope: scope, release: release)
            guard result.preview.inputSHA256 == input.byteSHA256 else {
                throw IncumbentFileAdapterWorkflowFailureV1.mismatchedPreview
            }
            return .inboundPreview(IncumbentFileAdapterInboundPreviewV1(
                rows: result.rows,
                mapping: result.preview,
                scope: scope,
                releaseID: release.releaseID,
                releaseSHA256: release.releaseSHA256,
                isZeroWrite: true
            ))
        case let .previewCanonicalImport(command):
            let bulk = try requireImportBulk(for: command.inbound)
            try validate(inbound: command.inbound, sourceSHA256: command.currentSourceSHA256)
            guard command.importPlan.workspaceID == command.inbound.scope.workspaceID,
                  command.importPlan.source.sourceSHA256 == command.inbound.mapping.inputSHA256,
                  command.importPlan.mappingProfileSHA256
                    == command.inbound.mapping.mappingManifestSHA256 else {
                throw IncumbentFileAdapterWorkflowFailureV1.mismatchedPreview
            }
            let preview = try bulk.preview(
                importPlan: command.importPlan,
                bulkPlan: command.bulkPlan,
                currentSourceSHA256: command.currentSourceSHA256,
                currentWorkspaceRevisionSHA256: command.currentWorkspaceRevisionSHA256
            )
            return .canonicalPreview(try IncumbentFileAdapterC08ReentryV1(
                inbound: command.inbound,
                preview: preview
            ))
        case let .beginCanonicalImport(command):
            let bulk = try requireImportBulk(for: command.reentry.inbound)
            try validate(inbound: command.reentry.inbound, sourceSHA256: command.currentSourceSHA256)
            _ = try IncumbentFileAdapterC08ReentryV1(
                inbound: command.reentry.inbound,
                preview: command.reentry.preview
            )
            return .canonicalSession(try bulk.begin(
                sessionID: command.sessionID,
                preview: command.reentry.preview,
                currentSourceSHA256: command.currentSourceSHA256,
                currentWorkspaceRevisionSHA256: command.currentWorkspaceRevisionSHA256
            ))
        case let .commitOrCancelCanonicalImport(command):
            let bulk = try requireImportBulk(for: command.reentry.inbound)
            try validate(inbound: command.reentry.inbound, sourceSHA256: command.currentSourceSHA256)
            _ = try IncumbentFileAdapterC08ReentryV1(
                inbound: command.reentry.inbound,
                preview: command.reentry.preview
            )
            return .canonicalSession(try bulk.commitFirstMissingChunk(
                session: command.session,
                importPlan: command.reentry.preview.importPlan,
                bulkPlan: command.reentry.preview.bulkPlan,
                currentSourceSHA256: command.currentSourceSHA256,
                currentWorkspaceRevisionSHA256: command.currentWorkspaceRevisionSHA256,
                cancellationRequested: command.cancellationRequested
            ))
        case let .export(projections, scope, date):
            let release = try requireRelease(scope: scope, at: date)
            let result = try exchange.render(projections: projections, scope: scope, at: date)
            try result.manifest.validate(scope: scope, release: release, output: result.data)
            return .exported(data: result.data, manifest: result.manifest)
        case let .recover(scope, date, plan, sourceSHA256, canonicalMutation, cleanup):
            _ = try requireRelease(scope: scope, at: date)
            try plan.validate()
            guard plan.scopeSHA256 == scope.scopeSHA256,
                  plan.workspaceID == scope.workspaceID,
                  plan.mappingManifestSHA256
                    == registry.currentProductionReleases.first?.mappingManifest.manifestSHA256 else {
                throw IncumbentFileAdapterWorkflowFailureV1.mismatchedPreview
            }
            return .recovered(try exchange.recover(
                plan: plan,
                observedSourceSHA256: sourceSHA256,
                canonicalMutation: canonicalMutation,
                cleanup: cleanup
            ))
        }
    }

    private func requireRelease(
        scope: IncumbentExchangeScopeV1,
        at date: Date
    ) throws -> IncumbentFileProfileReleaseV1 {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        guard let release = registry.currentProductionReleases.first else {
            throw IncumbentFileAdapterWorkflowFailureV1.disabledNoSelectedProfile
        }
        let selected = try registry.selectedRelease(at: date)
        guard selected == release,
              scope.releaseID == release.releaseID,
              scope.releaseSHA256 == release.releaseSHA256 else {
            throw IncumbentFileAdapterWorkflowFailureV1.exactReleaseRequired
        }
        try scope.validate(release: release)
        return release
    }

    private func requireRelease(
        id: UUID,
        sha256: String
    ) throws -> IncumbentFileProfileReleaseV1 {
        guard let release = registry.currentProductionReleases.first else {
            throw IncumbentFileAdapterWorkflowFailureV1.disabledNoSelectedProfile
        }
        guard release.releaseID == id, release.releaseSHA256 == sha256 else {
            throw IncumbentFileAdapterWorkflowFailureV1.exactReleaseRequired
        }
        return release
    }

    private func requireImportBulk(
        for inbound: IncumbentFileAdapterInboundPreviewV1
    ) throws -> ImportBulkCoordinatorV1 {
        _ = try requireRelease(id: inbound.releaseID, sha256: inbound.releaseSHA256)
        guard let importBulk else { throw IncumbentFileAdapterWorkflowFailureV1.importBulkUnavailable }
        return importBulk
    }

    private func validate(
        inbound: IncumbentFileAdapterInboundPreviewV1,
        sourceSHA256: String
    ) throws {
        let release = try requireRelease(id: inbound.releaseID, sha256: inbound.releaseSHA256)
        try inbound.scope.validate(release: release)
        try inbound.mapping.validate(scope: inbound.scope, release: release)
        guard inbound.isZeroWrite,
              inbound.mapping.inputSHA256 == sourceSHA256,
              inbound.rows.count == inbound.mapping.rowCount else {
            throw IncumbentFileAdapterWorkflowFailureV1.mismatchedPreview
        }
        try inbound.rows.forEach { try $0.validate(release: release) }
    }
}

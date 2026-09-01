import Foundation
import SwiftData
import UIKit

struct SearchCanonicalProjectionPageV1: Equatable, Sendable {
    let requestedCanonicalOffset: Int
    let nextCanonicalOffset: Int
    let isComplete: Bool
    let records: [SearchIndexProjectionRecordV1]

    init(
        requestedCanonicalOffset: Int,
        nextCanonicalOffset: Int,
        isComplete: Bool,
        records: [SearchIndexProjectionRecordV1]
    ) throws {
        guard requestedCanonicalOffset >= 0,
              nextCanonicalOffset >= requestedCanonicalOffset else {
            throw SearchContractFailureV1.limitExceeded
        }
        let canonicalIdentityCount = Set(records.map {
            $0.sourceKind.rawValue + "\u{0}" + $0.sourceStableID
        }).count
        let canonicalAdvance = nextCanonicalOffset - requestedCanonicalOffset
        guard canonicalAdvance <= SearchIndexRebuildCoordinatorV1.pageSize,
              (isComplete || nextCanonicalOffset > requestedCanonicalOffset),
              (records.isEmpty || nextCanonicalOffset > requestedCanonicalOffset),
              canonicalIdentityCount <= canonicalAdvance,
              records.count <= SearchIndexRebuildCoordinatorV1.maximumProjectionRowsPerPage,
              records == records.sorted(),
              Set(records.map(\.projectionIdentity)).count == records.count else {
            throw SearchContractFailureV1.limitExceeded
        }
        self.requestedCanonicalOffset = requestedCanonicalOffset
        self.nextCanonicalOffset = nextCanonicalOffset
        self.isComplete = isComplete
        self.records = records
    }
}

/// The source must read from an immutable snapshot at the supplied revision.
/// It must fail rather than silently advance to a newer canonical commit.
protocol SearchCanonicalProjectionSourceV1: Sendable {
    func currentSearchSourceRevision() async throws -> SearchSourceRevisionV1
    func searchProjectionPage(
        at source: SearchSourceRevisionV1,
        canonicalOffset: Int,
        limit: Int
    ) async throws -> SearchCanonicalProjectionPageV1
    func discardCachedSearchProjectionSnapshot() async
}

extension SearchCanonicalProjectionSourceV1 {
    func discardCachedSearchProjectionSnapshot() async {}
}

protocol SearchOperationalStatusProvidingV1: Sendable {
    func backupStaleCanonicalIdentities(
        at source: SearchSourceRevisionV1
    ) async throws -> Set<SearchCanonicalRecordIdentityV1>
}

enum C08ImportBulkSearchRebuildBoundaryV1 {
    static let rebuildReadsOnlyCanonicalC08Rows = true
    static let rebuildWritesNoC08CanonicalState = true
    static let rawImportSourceOrCustomerFieldsIndexed = false
    static func validate() -> Bool {
        rebuildReadsOnlyCanonicalC08Rows
            && rebuildWritesNoC08CanonicalState
            && !rawImportSourceOrCustomerFieldsIndexed
    }
}

private struct AuthorityCriterionClassificationChainKeyV1: Hashable {
    let activityID: UUID
    let findingID: UUID
    let criterionID: String
}

private struct AuthorityCriterionClassificationSearchRecordV1 {
    let value: FindingClassificationBindingV1
    let activityID: UUID
}

/// Resolves an append-only predecessor chain to exactly one current head for
/// every logical group. A search rebuild must not choose a newest row, merge
/// forks, or silently bridge a chain into another workspace/group.
private func authorityCriterionUniqueHeadsV1<Value, Group: Hashable>(
    values: [Value],
    expectedWorkspace: WorkspaceID,
    id: (Value) -> UUID,
    workspace: (Value) -> WorkspaceID,
    predecessor: (Value) -> UUID?,
    group: (Value) -> Group
) throws -> [Value] {
    var byID: [UUID: Value] = [:]
    for value in values {
        let valueID = id(value)
        guard valueID != SearchContractValidationV1.zeroUUID,
              workspace(value) == expectedWorkspace,
              byID[valueID] == nil else {
            throw SearchContractFailureV1.invalidContext
        }
        byID[valueID] = value
    }

    var childCounts: [UUID: Int] = [:]
    for value in values {
        guard let predecessorID = predecessor(value) else { continue }
        guard predecessorID != id(value),
              let parent = byID[predecessorID],
              workspace(parent) == expectedWorkspace,
              group(parent) == group(value) else {
            throw SearchContractFailureV1.invalidContext
        }
        childCounts[predecessorID, default: 0] += 1
        guard childCounts[predecessorID] == 1 else {
            throw SearchContractFailureV1.invalidContext
        }
    }

    // A cycle has no head, so detect it explicitly rather than allowing a
    // cyclic group to disappear behind an empty head set.
    for value in values {
        var visited: Set<UUID> = []
        var cursor = value
        while let predecessorID = predecessor(cursor) {
            let cursorID = id(cursor)
            guard visited.insert(cursorID).inserted,
                  predecessorID != cursorID,
                  let parent = byID[predecessorID],
                  workspace(parent) == expectedWorkspace,
                  group(parent) == group(cursor) else {
                throw SearchContractFailureV1.invalidContext
            }
            cursor = parent
        }
    }

    var headsByGroup: [Group: [Value]] = [:]
    for value in values where childCounts[id(value), default: 0] == 0 {
        headsByGroup[group(value), default: []].append(value)
    }
    guard headsByGroup.count == Set(values.map(group)).count,
          headsByGroup.values.allSatisfy({ $0.count == 1 }) else {
        throw SearchContractFailureV1.invalidContext
    }
    return headsByGroup.values.compactMap { $0.first }
}

/// Main-actor SwiftData projection source for the active generation. Paging is
/// over canonical entities (not projection rows) and is bound to the writer's
/// exact revision before and after every fetch.
@MainActor
final class SwiftDataSearchCanonicalProjectionSourceV1: SearchCanonicalProjectionSourceV1 {
    private struct CanonicalValue {
        let kind: SearchSourceKindV1
        let stableID: String
        let display: String
        let summary: String
        let breadcrumb: [String]
        let status: String
        let dueAt: Date?
        let timestamp: Date
        /// Role history is intentionally a bounded, non-contact summary.  It
        /// is only populated for the additive C38 party projection.
        let roleSummary: String = ""
        /// C39 fields contain stable semantic labels and recorded states only;
        /// raw product identifier values never enter the disposable index.
        let semanticKindSummary: String = ""
        let semanticCapabilitySummary: String = ""
        let lifecycleEventSummary: String = ""
        let productIdentityStateSummary: String = ""
        let workSubjectScopeSummary: String = ""
        let authoritySourceSummary: String = ""
        let applicabilityDispositionSummary: String = ""
        let criterionResultSummary: String = ""
        let severityLevelSummary: String = ""
        let measurementProtocolSummary: String = ""
        /// C41 fields are restricted to descriptor and current-head facts.
        /// Relationship history, actors, locators, and topology internals
        /// never enter the disposable index.
        let functionalRelationshipDescriptorSummary: String = ""
        let functionalRelationshipDirectionSummary: String = ""
        let functionalRelationshipStateSummary: String = ""
        let functionalRelationshipEndpointSummary: String = ""
        /// C13 search values are intentionally limited to audience,
        /// disposition, limitation, and projection-version metadata.
        let assuranceAudienceSummary: String = ""
        let assuranceDispositionSummary: String = ""
        let assuranceLimitationSummary: String = ""
        let assuranceProjectionVersionSummary: String = ""
        /// C14 search values are current-head, typed review/change/action
        /// state only. Reasons, actor snapshots, evidence references, and
        /// historical revisions never become disposable index text.
        let inspectionReviewStateSummary: String = ""
        let inspectionReviewDispositionSummary: String = ""
        let changeRequestStateSummary: String = ""
        let correctiveActionStateSummary: String = ""
        let inspectionReviewProjectionVersionSummary: String = ""
        /// C15 search values are packet/item current-head metadata only.
        /// Claims, leases, actors, result links, and review-exception digests
        /// remain in the canonical packet snapshot.
        let workPacketManifestStateSummary: String = ""
        let workPacketItemStateSummary: String = ""
        let workPacketConflictStateSummary: String = ""
        let workPacketProjectionVersionSummary: String = ""
    }

    let registry: SearchableFieldRegistryV1
    private let modelContext: ModelContext
    private let workspaceID: UUID
    private let generationID: UUID
    private let revisionProvider: @MainActor () throws -> SearchSourceRevisionV1
    private let operationalStatusProvider: (any SearchOperationalStatusProvidingV1)?
    private let includeAccountability: Bool
    private let includeAssetSemantics: Bool
    private let includeAuthorityCriterion: Bool
    private let includeFunctionalRelationships: Bool
    private let includeAssurance: Bool
    private let includeInspectionReview: Bool
    private let includeWorkPacket: Bool
    private var snapshotRevision: SearchSourceRevisionV1?
    private var snapshotValues: [CanonicalValue]?
    private var snapshotBackupStaleIdentities: Set<SearchCanonicalRecordIdentityV1> = []

    init(
        modelContext: ModelContext,
        workspaceID: UUID,
        generationID: UUID,
        revisionProvider: @escaping @MainActor () throws -> SearchSourceRevisionV1,
        operationalStatusProvider: (any SearchOperationalStatusProvidingV1)? = nil,
        includeAccountability: Bool = false,
        includeAssetSemantics: Bool = false,
        includeAuthorityCriterion: Bool = false,
        includeFunctionalRelationships: Bool = false,
        includeAssurance: Bool = false,
        includeInspectionReview: Bool = false,
        includeWorkPacket: Bool = false
    ) throws {
        guard workspaceID != SearchContractValidationV1.zeroUUID,
              generationID != SearchContractValidationV1.zeroUUID else {
            throw SearchContractFailureV1.invalidRevision
        }
        self.modelContext = modelContext
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.revisionProvider = revisionProvider
        self.operationalStatusProvider = operationalStatusProvider
        // C14 is a complete additive registry. Enabling its review history
        // also enables every preceding public projection so the registry's
        // exact identity set remains unambiguous.
        let c15 = includeWorkPacket
        let c14 = includeInspectionReview || c15
        let resolvedAccountability = includeAccountability || c14
        let resolvedAssetSemantics = includeAssetSemantics || c14
        let resolvedAuthorityCriterion = includeAuthorityCriterion || c14
        let resolvedFunctionalRelationships = includeFunctionalRelationships || c14
        let resolvedAssurance = includeAssurance || c14
        self.includeAccountability = resolvedAccountability
        self.includeAssetSemantics = resolvedAssetSemantics
        self.includeAuthorityCriterion = resolvedAuthorityCriterion
        self.includeFunctionalRelationships = resolvedFunctionalRelationships
        self.includeAssurance = resolvedAssurance
        self.includeInspectionReview = c14
        self.includeWorkPacket = c15
        registry = try Self.makeExtendedRegistry(
            includeAccountability: resolvedAccountability,
            includeAssetSemantics: resolvedAssetSemantics,
            includeAuthorityCriterion: resolvedAuthorityCriterion,
            includeFunctionalRelationships: resolvedFunctionalRelationships,
            includeAssurance: resolvedAssurance,
            includeInspectionReview: c14,
            includeWorkPacket: c15
        )
    }

    func currentSearchSourceRevision() async throws -> SearchSourceRevisionV1 {
        try validatedCurrentRevision()
    }

    func discardCachedSearchProjectionSnapshot() async {
        snapshotRevision = nil
        snapshotValues = nil
        snapshotBackupStaleIdentities = []
    }

    func searchProjectionPage(
        at source: SearchSourceRevisionV1,
        canonicalOffset: Int,
        limit: Int
    ) async throws -> SearchCanonicalProjectionPageV1 {
        try Task.checkCancellation()
        guard source == (try validatedCurrentRevision()),
              canonicalOffset >= 0,
              limit > 0,
              limit <= SearchIndexRebuildCoordinatorV1.pageSize else {
            throw SearchIndexRebuildFailureV1.sourceChangedDuringRebuild
        }
        let canonical = try await canonicalValues(at: source)
        guard canonical.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              canonicalOffset <= canonical.count else {
            throw SearchIndexRebuildFailureV1.recordLimitExceeded
        }
        let end = min(canonical.count, canonicalOffset + limit)
        var records: [SearchIndexProjectionRecordV1] = []
        for (index, value) in canonical[canonicalOffset..<end].enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            records.append(contentsOf: try project(value, source: source))
        }
        try Task.checkCancellation()
        guard source == (try validatedCurrentRevision()) else {
            throw SearchIndexRebuildFailureV1.sourceChangedDuringRebuild
        }
        let page = try SearchCanonicalProjectionPageV1(
            requestedCanonicalOffset: canonicalOffset,
            nextCanonicalOffset: end,
            isComplete: end == canonical.count,
            records: records.sorted()
        )
        if page.isComplete {
            snapshotRevision = nil
            snapshotValues = nil
            snapshotBackupStaleIdentities = []
        }
        return page
    }
}

@MainActor
private extension SwiftDataSearchCanonicalProjectionSourceV1 {
    func validatedCurrentRevision() throws -> SearchSourceRevisionV1 {
        let revision = try revisionProvider()
        guard revision.workspaceID == workspaceID,
              revision.generationID == generationID else {
            throw SearchContractFailureV1.invalidRevision
        }
        if let snapshotRevision, snapshotRevision != revision {
            self.snapshotRevision = nil
            snapshotValues = nil
            snapshotBackupStaleIdentities = []
        }
        return revision
    }

    func canonicalValues(at source: SearchSourceRevisionV1) async throws -> [CanonicalValue] {
        if snapshotRevision == source, let snapshotValues { return snapshotValues }
        var values: [CanonicalValue] = []
        let semanticByAsset = includeAssetSemantics
            ? try assetSemanticSearchValues()
            : [:]
        let authorityByActivity = includeAuthorityCriterion
            ? try authorityCriterionSearchValues()
            : [:]
        let functionalRelationshipValues = includeFunctionalRelationships
            ? try functionalRelationshipSearchValues()
            : []
        let assuranceValues = includeAssurance
            ? try assuranceSearchValues()
            : []
        let inspectionReviewValues = includeInspectionReview
            ? try inspectionReviewSearchValues()
            : []
        let workPacketValues = includeWorkPacket
            ? try workPacketSearchValues()
            : []
        values += try modelContext.fetch(FetchDescriptor<Asset>()).map {
            let semantic = semanticByAsset[$0.id]
            return CanonicalValue(kind: .asset, stableID: try stableKey(kind: .asset, id: $0.id),
                display: $0.label, summary: $0.label, breadcrumb: [], status: "active",
                dueAt: nil, timestamp: $0.updatedAt,
                semanticKindSummary: semantic?.kind ?? "",
                semanticCapabilitySummary: semantic?.capability ?? "",
                lifecycleEventSummary: semantic?.lifecycle ?? "",
                productIdentityStateSummary: semantic?.productState ?? "",
                workSubjectScopeSummary: semantic?.scope ?? "")
        }
        values += try modelContext.fetch(FetchDescriptor<Site>()).map {
            CanonicalValue(kind: .location, stableID: try stableKey(kind: .site, id: $0.id),
                display: $0.label, summary: $0.address ?? $0.label,
                breadcrumb: [$0.label], status: "active", dueAt: nil, timestamp: $0.updatedAt)
        }
        values += try modelContext.fetch(FetchDescriptor<LocationNodeRow>())
            .filter { $0.workspaceID == workspaceID }
            .map {
                CanonicalValue(kind: .location, stableID: try stableKey(kind: .locationNode, id: $0.id),
                    display: $0.label, summary: $0.shortCode ?? $0.label,
                    breadcrumb: [$0.label], status: $0.state, dueAt: nil, timestamp: $0.occurredAt)
            }
        values += try modelContext.fetch(FetchDescriptor<WorkflowRecord>()).map {
            let summary = $0.workDescription ?? $0.note ?? $0.outcomeKey ?? $0.stage
            let authority = authorityByActivity[$0.id]
            return CanonicalValue(kind: .work, stableID: try stableKey(kind: .workflowRecord, id: $0.id),
                display: summary, summary: summary, breadcrumb: [], status: $0.state,
                dueAt: nil, timestamp: $0.completedAt ?? $0.startedAt,
                authoritySourceSummary: authority?.sources.sorted().joined(separator: " ") ?? "",
                applicabilityDispositionSummary: authority?.dispositions.sorted().joined(separator: " ") ?? "",
                criterionResultSummary: authority?.results.sorted().joined(separator: " ") ?? "",
                severityLevelSummary: authority?.severityLevels.sorted().joined(separator: " ") ?? "",
                measurementProtocolSummary: authority?.measurementProtocols.sorted().joined(separator: " ") ?? "")
        }
        values += try modelContext.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>())
            .filter { $0.workspaceID == workspaceID }
            .map { row in
                let envelope = try row.value()
                let projection = try ActivityContractSearchProjectionV2(envelope: envelope)
                let closeoutSummary = [
                    projection.closeoutKind,
                    projection.closeoutDisposition,
                ].compactMap { $0 }.joined(separator: " ")
                return CanonicalValue(
                    kind: .work,
                    stableID: try stableKey(kind: .activitySessionEnvelope, id: projection.activityID),
                    display: projection.title,
                    summary: ([projection.kind.rawValue, projection.title, closeoutSummary]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")),
                    breadcrumb: [],
                    status: ([projection.state.rawValue, closeoutSummary]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")),
                    dueAt: nil, timestamp: envelope.finalizedAt ?? envelope.startedAt
                )
            }
        values += try modelContext.fetch(FetchDescriptor<Issue>()).map {
            CanonicalValue(kind: .work, stableID: try stableKey(kind: .issue, id: $0.id),
                display: $0.labelDisplaySnapshot, summary: $0.labelDisplaySnapshot,
                breadcrumb: [], status: $0.status, dueAt: $0.updatedAt,
                timestamp: $0.updatedAt)
        }
        values += try modelContext.fetch(FetchDescriptor<Report>()).map {
            let display = "Report \($0.id.uuidString.lowercased())"
            return CanonicalValue(kind: .report, stableID: try stableKey(kind: .report, id: $0.id),
                display: display, summary: display, breadcrumb: [], status: $0.pdfState,
                dueAt: nil, timestamp: $0.createdAt)
        }
        // C08 contributes only bounded canonical metadata. Never index mapped
        // source/target fields, source bytes, imported row values, or customer
        // data; the three stable digests and lifecycle states are sufficient
        // to locate durable operational/audit state.
        values += try modelContext.fetch(FetchDescriptor<ImportMappingProfileRowV1>())
            .filter { $0.workspaceID == workspaceID }
            .map { row in
                let profile = try row.value()
                return CanonicalValue(
                    kind: .report,
                    stableID: try stableKey(kind: .importMappingProfile, id: profile.profileID),
                    display: "Saved import mapping",
                    summary: "schema \(profile.schemaRelease) \(profile.schemaSHA256)",
                    breadcrumb: [], status: "saved", dueAt: nil,
                    timestamp: Date(timeIntervalSince1970: 0)
                )
            }
        values += try modelContext.fetch(FetchDescriptor<BulkSessionRowV1>())
            .filter { $0.workspaceID == workspaceID }
            .map { row in
                let session = try row.value()
                return CanonicalValue(
                    kind: .report,
                    stableID: try stableKey(kind: .bulkSession, id: session.sessionID),
                    display: "Import bulk session",
                    summary: "\(session.state.rawValue) \(session.bulkPlanSHA256)",
                    breadcrumb: [], status: session.state.rawValue, dueAt: nil,
                    timestamp: Date(timeIntervalSince1970: 0)
                )
            }
        values += try modelContext.fetch(FetchDescriptor<BulkCommitReceiptRowV1>())
            .filter { $0.workspaceID == workspaceID }
            .map { row in
                let receipt = try row.value()
                return CanonicalValue(
                    kind: .report,
                    stableID: try stableKey(kind: .bulkCommitReceipt, id: receipt.receiptID),
                    display: "Import bulk receipt",
                    summary: "chunk \(receipt.chunkIndex) \(receipt.receiptSHA256)",
                    breadcrumb: [], status: receipt.disposition.rawValue, dueAt: nil,
                    timestamp: Date(timeIntervalSince1970: 0)
                )
            }
        // C10 indexes the three business facts only.  Typed receipts, waiver
        // limitation text, actor snapshots, and canonical media bytes remain
        // unindexed so a rebuild cannot disclose advisory-only details.
        let evidenceQualityRules = try modelContext.fetch(FetchDescriptor<EvidenceQualityRuleSetRowV1>())
            .map { try $0.value() }.filter { $0.workspaceID == workspaceID }
        values += try evidenceQualityRules.map { ruleSet in
            CanonicalValue(kind: .report,
                           stableID: try stableKey(kind: .evidenceQualityRuleSet, id: ruleSet.ruleSetID),
                           display: "Evidence quality rules",
                           summary: "\(ruleSet.policyVersion) \(ruleSet.ruleSetSHA256)",
                           breadcrumb: [], status: "advisory", dueAt: nil, timestamp: ruleSet.recordedAt)
        }
        let evidenceQualityAssessments = try modelContext.fetch(FetchDescriptor<EvidenceQualityAssessmentRowV1>())
            .map { row -> EvidenceQualityAssessmentV1 in
                for ruleSet in evidenceQualityRules {
                    if let value = try? row.value(ruleSet: ruleSet) { return value }
                }
                throw SearchContractFailureV1.invalidRevision
            }.filter { $0.workspaceID == workspaceID }
        values += try evidenceQualityAssessments.map { assessment in
            CanonicalValue(kind: .report,
                           stableID: try stableKey(kind: .evidenceQualityAssessment, id: assessment.assessmentID),
                           display: "Evidence quality assessment",
                           summary: "\(assessment.evidence.evidenceID) r\(assessment.evidence.evidenceRevision) \(assessment.assessmentSHA256)",
                           breadcrumb: [], status: "advisory", dueAt: nil, timestamp: assessment.assessedAt)
        }
        let evidenceQualityWaivers = try modelContext.fetch(FetchDescriptor<EvidenceQualityWaiverRowV1>())
            .map { row -> EvidenceQualityWaiverV1 in
                for assessment in evidenceQualityAssessments {
                    if let value = try? row.value(assessment: assessment) { return value }
                }
                throw SearchContractFailureV1.invalidRevision
            }.filter { $0.workspaceID == workspaceID }
        values += try evidenceQualityWaivers.map { waiver in
            CanonicalValue(kind: .report,
                           stableID: try stableKey(kind: .evidenceQualityWaiverEvent, id: waiver.waiverEventID),
                           display: "Evidence quality waiver",
                           summary: waiver.reason.rawValue,
                           breadcrumb: [], status: waiver.action.rawValue, dueAt: nil, timestamp: waiver.recordedAt)
        }
        // C11 indexes bounded review metadata only. Inbox text, snippet body,
        // actor data, and original media references remain unindexed.
        let fastSurveyInbox = try FastSurveyInboxSwiftDataQuerySourceV1(
            modelContext: modelContext, workspaceID: workspaceID
        ).snapshot()
        values += try fastSurveyInbox.inboxItems.map { item in
            CanonicalValue(kind: .report,
                           stableID: try stableKey(kind: .captureInboxItem, id: item.inboxItemID),
                           display: "Survey inbox capture",
                           summary: "\(item.mediaKind.rawValue) \(item.itemSHA256)",
                           breadcrumb: [], status: item.state.rawValue, dueAt: nil,
                           timestamp: item.temporalContext.recordedAtUTC)
        }
        values += try fastSurveyInbox.promotions.map { promotion in
            CanonicalValue(kind: .report,
                           stableID: try stableKey(kind: .capturePromotion, id: promotion.promotionID),
                           display: "Survey inbox promotion",
                           summary: "\(promotion.destination.kind.rawValue) \(promotion.promotionSHA256)",
                           breadcrumb: [], status: "promoted", dueAt: nil,
                           timestamp: promotion.promotedAt)
        }
        values += try fastSurveyInbox.snippets.map { snippet in
            CanonicalValue(kind: .report,
                           stableID: try stableKey(kind: .snippet, id: snippet.snippetID),
                           display: snippet.title,
                           summary: snippet.tags.joined(separator: " "),
                           breadcrumb: [], status: snippet.state.rawValue, dueAt: nil,
                           timestamp: snippet.editedAt)
        }
        // Frozen insertions must be present for deterministic rebuild/recovery,
        // but their inserted body and actor snapshot remain private.
        values += try fastSurveyInbox.snippetInsertions.map { insertion in
            CanonicalValue(kind: .report,
                           stableID: try stableKey(kind: .snippetInsertion, id: insertion.insertionEventID),
                           display: "Frozen snippet insertion",
                           summary: "snippet \(insertion.snippetID.uuidString.lowercased()) r\(insertion.snippetRevision) \(insertion.insertionSHA256)",
                           breadcrumb: [], status: "frozen", dueAt: nil,
                           timestamp: insertion.insertedAt)
        }
        // C13 alias and consolidation history is canonical, append-only
        // metadata. Index both former and survivor identities so a historic
        // identifier resolves without rewriting evidence or relationship rows.
        values += try modelContext.fetch(FetchDescriptor<EntityAliasLinkRowV1>())
            .map { try $0.value() }
            .filter { $0.workspaceID == workspaceID }
            .map { link in
                CanonicalValue(
                    kind: .report,
                    stableID: try stableKey(kind: .entityAliasLink, id: link.linkEventID),
                    display: "Entity alias",
                    summary: "\(link.alias.identity.id.uuidString.lowercased()) \(link.canonicalEntity.identity.id.uuidString.lowercased()) \(link.reason.rawValue)",
                    breadcrumb: [], status: "alias", dueAt: nil, timestamp: link.recordedAt
                )
            }
        values += try modelContext.fetch(FetchDescriptor<EntityConsolidationReceiptRowV1>())
            .map { try $0.value() }
            .filter { $0.workspaceID == workspaceID }
            .map { receipt in
                CanonicalValue(
                    kind: .report,
                    stableID: try stableKey(kind: .entityConsolidationReceipt, id: receipt.consolidationReceiptID),
                    display: "Entity consolidation",
                    summary: "\(receipt.source.identity.id.uuidString.lowercased()) \(receipt.survivor.identity.id.uuidString.lowercased()) \(receipt.disposition.rawValue)",
                    breadcrumb: [], status: receipt.disposition.rawValue, dueAt: nil, timestamp: receipt.recordedAt
                )
            }
        values += try modelContext.fetch(FetchDescriptor<AcceptedLabelGenerationSnapshotRow>())
            .filter { $0.workspaceID == workspaceID }
            .map { row in
                let snapshot = try row.value()
                let metadata = try AcceptedLabelSearchMetadataV1(snapshot)
                let display = metadata.snapshotID.uuidString.lowercased()
                let summary = ([metadata.snapshotSHA256] + metadata.assetIDs.map {
                    $0.uuidString.lowercased()
                }).joined(separator: " ")
                return CanonicalValue(
                    kind: .report,
                    stableID: try stableKey(
                        kind: .acceptedLabelGenerationSnapshot,
                        id: metadata.snapshotID
                    ),
                    display: display,
                    summary: summary,
                    breadcrumb: [],
                    status: metadata.disposition.rawValue,
                    dueAt: nil,
                    timestamp: snapshot.recordedAt
                )
            }
        values += functionalRelationshipValues
        values += assuranceValues
        values += inspectionReviewValues
        values += workPacketValues
        if includeAccountability {
            var rolesByParty: [UUID: Set<String>] = [:]
            var contactMetadataByParty: [UUID: Set<String>] = [:]
            let roleRows = try modelContext.fetch(FetchDescriptor<SitePartyRoleEventRow>())
                .filter { $0.workspaceID == workspaceID }
            for row in roleRows {
                let event = try row.value()
                rolesByParty[event.partyID, default: []].insert(event.role.rawValue)
            }
            let contactRows = try modelContext.fetch(FetchDescriptor<ServiceContactPointRow>())
                .filter { $0.workspaceID == workspaceID }
            for row in contactRows {
                let contact = try row.value()
                guard contact.lifecycle == .effective else { continue }
                contactMetadataByParty[contact.party.partyID, default: []].insert(
                    "CONTACT_\(contact.kind.rawValue)"
                )
                if contact.preferred {
                    contactMetadataByParty[contact.party.partyID, default: []].insert(
                        "PREFERRED_\(contact.kind.rawValue)"
                    )
                }
            }
            values += try modelContext.fetch(FetchDescriptor<ServicePartyRow>())
                .filter { $0.workspaceID == workspaceID }
                .map { row in
                    let party = try row.value()
                    let roles = (rolesByParty[party.partyID] ?? [])
                        .union(contactMetadataByParty[party.partyID] ?? [])
                        .sorted()
                    return CanonicalValue(
                        kind: .party,
                        stableID: try stableKey(kind: .serviceParty, id: party.partyID),
                        display: party.displayName,
                        summary: party.profileDescriptor ?? party.displayName,
                        breadcrumb: [],
                        status: party.state.rawValue,
                        dueAt: party.retiredAt,
                        timestamp: party.effectiveAt,
                        roleSummary: roles.isEmpty ? "NO_ROLE_RECORDED" : roles.joined(separator: " ")
                    )
                }
        }
        guard values.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchIndexRebuildFailureV1.recordLimitExceeded
        }
        let identities = values.map { $0.kind.rawValue + "\u{0}" + $0.stableID }
        guard Set(identities).count == identities.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        values.sort {
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.stableID < $1.stableID
        }
        guard source == (try validatedCurrentRevision()) else {
            throw SearchIndexRebuildFailureV1.sourceChangedDuringRebuild
        }
        let staleIdentities = try await operationalStatusProvider?
            .backupStaleCanonicalIdentities(at: source) ?? []
        var knownIdentities = Set<SearchCanonicalRecordIdentityV1>()
        for value in values {
            knownIdentities.insert(try SearchCanonicalRecordIdentityV1(
                sourceKind: value.kind,
                stableID: value.stableID
            ))
        }
        guard staleIdentities.isSubset(of: knownIdentities) else {
            throw SearchContractFailureV1.invalidContext
        }
        guard source == (try validatedCurrentRevision()) else {
            throw SearchIndexRebuildFailureV1.sourceChangedDuringRebuild
        }
        snapshotRevision = source
        snapshotValues = values
        snapshotBackupStaleIdentities = staleIdentities
        return values
    }

    private struct AssetSemanticSearchValue {
        var kinds: Set<String> = []
        var capabilities: Set<String> = []
        var lifecycleEvents: Set<String> = []
        var productStates: Set<String> = []
        var scopes: Set<String> = []

        var kind: String { kinds.sorted().joined(separator: " ") }
        var capability: String { capabilities.sorted().joined(separator: " ") }
        var lifecycle: String { lifecycleEvents.sorted().joined(separator: " ") }
        var productState: String { productStates.sorted().joined(separator: " ") }
        var scope: String { scopes.sorted().joined(separator: " ") }
    }

    func assetSemanticSearchValues() throws -> [UUID: AssetSemanticSearchValue] {
        var result: [UUID: AssetSemanticSearchValue] = [:]
        for row in try modelContext.fetch(FetchDescriptor<AssetKindBindingEventRow>())
            where row.workspaceID == workspaceID {
            let value = try row.value()
            var entry = result[value.assetID] ?? AssetSemanticSearchValue()
            entry.kinds.insert(value.semanticID)
            result[value.assetID] = entry
        }
        for row in try modelContext.fetch(FetchDescriptor<AssetWorkflowCapabilityBindingEventRow>())
            where row.workspaceID == workspaceID {
            let value = try row.value()
            var entry = result[value.assetID] ?? AssetSemanticSearchValue()
            entry.capabilities.formUnion(value.capabilityIDs.map(\.rawValue))
            result[value.assetID] = entry
        }
        for row in try modelContext.fetch(FetchDescriptor<AssetProductIdentityRow>())
            where row.workspaceID == workspaceID {
            let value = try row.value()
            var entry = result[value.assetID] ?? AssetSemanticSearchValue()
            entry.productStates.formUnion(value.identifiers.map { $0.reviewState.rawValue })
            result[value.assetID] = entry
        }
        for row in try modelContext.fetch(FetchDescriptor<AssetLifecycleEventRow>())
            where row.workspaceID == workspaceID {
            let value = try row.value()
            var entry = result[value.record.assetID] ?? AssetSemanticSearchValue()
            entry.lifecycleEvents.insert(value.kind.rawValue)
            result[value.record.assetID] = entry
        }
        for row in try modelContext.fetch(FetchDescriptor<WorkSubjectScopeSnapshotRow>())
            where row.workspaceID == workspaceID {
            let value = try row.value()
            for subject in value.subjects {
                let assetID = subject.kind == .asset ? subject.subjectID : subject.ownerAssetID
                guard let assetID else { continue }
                var entry = result[assetID] ?? AssetSemanticSearchValue()
                entry.scopes.insert(subject.kind.rawValue)
                result[assetID] = entry
            }
            for semanticBinding in value.semanticBindings {
                var entry = result[semanticBinding.assetID] ?? AssetSemanticSearchValue()
                entry.kinds.insert(semanticBinding.semanticID)
                result[semanticBinding.assetID] = entry
            }
        }
        return result
    }

    private struct AuthorityCriterionSearchValue {
        var sources: Set<String> = []
        var dispositions: Set<String> = []
        var results: Set<String> = []
        var severityLevels: Set<String> = []
        var measurementProtocols: Set<String> = []
    }

    /// Reads only descriptor releases and the one current head selected by the
    /// canonical C41 projection builder. Any orphan, fork, cycle, unknown
    /// descriptor, or invalid transition fails the rebuild rather than being
    /// silently indexed.
    func functionalRelationshipSearchValues() throws -> [CanonicalValue] {
        let expectedWorkspace = WorkspaceID(rawValue: workspaceID)
        let descriptorRows = try modelContext.fetch(
            FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>()
        ).filter { $0.workspaceID == workspaceID }
        let descriptors = try descriptorRows.map { try $0.value() }
        var descriptorByID: [UUID: FunctionalRelationshipTypeDescriptorV1] = [:]
        for descriptor in descriptors {
            guard descriptor.workspaceID == expectedWorkspace,
                  descriptorByID[descriptor.descriptorReleaseID] == nil else {
                throw SearchContractFailureV1.invalidContext
            }
            descriptorByID[descriptor.descriptorReleaseID] = descriptor
        }
        let eventRows = try modelContext.fetch(
            FetchDescriptor<AssetFunctionalRelationshipEventRow>()
        ).filter { $0.workspaceID == workspaceID }
        let events = try eventRows.map { try $0.value() }
        let current = try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: expectedWorkspace,
            events: events,
            descriptors: descriptors
        ).currentRelationships

        // Placement history is canonical context, never indexed content. When
        // both endpoints have a current placement, same-site descriptors must
        // agree with it; a cross-site row is rejected instead of becoming a
        // misleading search hit. Missing placement is left unresolved for a
        // descriptor that explicitly permits cross-site local associations.
        let placementValues = try modelContext.fetch(
            FetchDescriptor<AssetPlacementEventRow>()
        ).filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        let currentPlacements = try authorityCriterionUniqueHeadsV1(
            values: placementValues,
            expectedWorkspace: expectedWorkspace,
            id: { $0.id },
            workspace: { $0.workspaceID },
            predecessor: { $0.predecessorEventID },
            group: { $0.assetID }
        )
        let siteByAsset = Dictionary(uniqueKeysWithValues: currentPlacements.map {
            ($0.assetID, $0.siteID)
        })
        for event in current {
            guard let descriptor = descriptorByID[event.descriptor.descriptorReleaseID] else {
                throw SearchContractFailureV1.invalidContext
            }
            if descriptor.sitePolicy == .sameSiteRequired,
               let sourceSite = siteByAsset[event.sourceAssetID],
               let targetSite = siteByAsset[event.targetAssetID],
               sourceSite != targetSite {
                throw SearchContractFailureV1.invalidContext
            }
        }

        var values: [CanonicalValue] = []
        for descriptor in descriptors.sorted(by: {
            ($0.semanticID, $0.descriptorReleaseID.uuidString)
                < ($1.semanticID, $1.descriptorReleaseID.uuidString)
        }) {
            values.append(CanonicalValue(
                kind: .asset,
                stableID: "functional-descriptor-\(descriptor.descriptorReleaseID.uuidString.lowercased())",
                display: descriptor.semanticID,
                summary: descriptor.semanticID,
                breadcrumb: [],
                status: "descriptor",
                dueAt: nil,
                timestamp: descriptor.releasedAt,
                functionalRelationshipDescriptorSummary: descriptor.semanticID,
                functionalRelationshipDirectionSummary: descriptor.direction.rawValue,
                functionalRelationshipStateSummary: "DESCRIPTOR",
                functionalRelationshipEndpointSummary: ""
            ))
        }
        for event in current.sorted(by: {
            ($0.relationshipID.uuidString, $0.revision)
                < ($1.relationshipID.uuidString, $1.revision)
        }) {
            guard let descriptor = descriptorByID[event.descriptor.descriptorReleaseID],
                  descriptor.descriptorSHA256 == event.descriptor.descriptorSHA256 else {
                throw SearchContractFailureV1.invalidContext
            }
            let state = event.action == .superseded ? "SUPERSEDED" : "ACTIVE"
            values.append(CanonicalValue(
                kind: .asset,
                stableID: "functional-relationship-\(event.relationshipID.uuidString.lowercased())",
                display: descriptor.semanticID,
                summary: descriptor.semanticID,
                breadcrumb: [],
                status: state.lowercased(),
                dueAt: nil,
                timestamp: event.recordedAt,
                functionalRelationshipDescriptorSummary: descriptor.semanticID,
                functionalRelationshipDirectionSummary: descriptor.direction.rawValue,
                functionalRelationshipStateSummary: state,
                functionalRelationshipEndpointSummary: "\(event.sourceAssetID.uuidString.lowercased()) \(event.targetAssetID.uuidString.lowercased())"
            ))
        }
        return values
    }

    /// Reads only current assurance-manifest heads. The index contains typed
    /// audience/disposition/limitation/version metadata; it never contains
    /// claim text, evidence identifiers/digests, media/content, or actor data.
    func assuranceSearchValues() throws -> [CanonicalValue] {
        let expectedWorkspace = WorkspaceID(rawValue: workspaceID)
        let manifests = try modelContext.fetch(FetchDescriptor<AssuranceManifestRow>())
            .filter { $0.workspaceID == workspaceID }
            .map { try $0.value() }
        let heads = try authorityCriterionUniqueHeadsV1(
            values: manifests,
            expectedWorkspace: expectedWorkspace,
            id: { $0.manifestID },
            workspace: { $0.workspaceID },
            predecessor: { $0.supersedesManifestID },
            group: { "\($0.snapshotSHA256):\($0.audience.rawValue):\($0.projectionVersion)" }
        )
        return try heads.sorted {
            $0.manifestID.uuidString.lowercased() < $1.manifestID.uuidString.lowercased()
        }.map { manifest in
            try manifest.validate()
            for link in manifest.includedLinks + manifest.excludedLinks {
                try link.validate(visibility: link.visibility)
            }
            let limitationValues = Set(manifest.excludedLinks.map { $0.decision.limitation.rawValue })
            let limitationSummary = limitationValues.isEmpty
                ? EvidenceLimitationV1.none.rawValue
                : limitationValues.sorted().joined(separator: " ")
            let dispositionValues = Set((manifest.includedLinks.map {
                EvidenceInclusionDispositionV1.included.rawValue
            } + manifest.excludedLinks.map {
                EvidenceInclusionDispositionV1.excluded.rawValue
            }))
            return CanonicalValue(
                kind: .report,
                stableID: "assurance-\(manifest.manifestID.uuidString.lowercased())",
                display: "Evidence assurance",
                summary: "Evidence assurance",
                breadcrumb: [],
                status: "provisional",
                dueAt: nil,
                timestamp: manifest.recordedAt,
                assuranceAudienceSummary: manifest.audience.rawValue,
                assuranceDispositionSummary: dispositionValues.sorted().joined(separator: " "),
                assuranceLimitationSummary: limitationSummary,
                assuranceProjectionVersionSummary: manifest.projectionVersion
            )
        }
    }

    private struct InspectionReviewSearchValue {
        var reviewState: String = ""
        var dispositions: Set<String> = []
        var changeStates: Set<String> = []
        var actionStates: Set<String> = []
        var timestamp: Date?

        mutating func record(_ value: Date) {
            timestamp = max(timestamp ?? value, value)
        }
    }

    /// Reads the C14 rows only through their current-head projections. The
    /// resulting records carry typed state/version metadata; reasons, actor
    /// snapshots, evidence references, and historical revisions stay in the
    /// canonical completed snapshot and are never copied into the index.
    func inspectionReviewSearchValues() throws -> [CanonicalValue] {
        let expectedWorkspace = WorkspaceID(rawValue: workspaceID)
        let transitions = try modelContext.fetch(
            FetchDescriptor<InspectionReviewTransitionRow>()
        ).filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        let dispositions = try modelContext.fetch(
            FetchDescriptor<ReviewDispositionRow>()
        ).filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        let requests = try modelContext.fetch(
            FetchDescriptor<ChangeRequestRow>()
        ).filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        let actions = try modelContext.fetch(
            FetchDescriptor<CorrectiveActionEventRow>()
        ).filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        let policies = try modelContext.fetch(
            FetchDescriptor<CorrectiveActionPolicyRow>()
        ).filter { $0.workspaceID == workspaceID }.map { try $0.value() }

        guard !transitions.isEmpty else {
            guard dispositions.isEmpty, requests.isEmpty, actions.isEmpty else {
                throw SearchContractFailureV1.invalidContext
            }
            return []
        }

        try transitions.forEach {
            try $0.validate()
            guard $0.workspaceID == expectedWorkspace else {
                throw SearchContractFailureV1.invalidContext
            }
        }
        try dispositions.forEach {
            try $0.validate()
            guard $0.workspaceID == expectedWorkspace else {
                throw SearchContractFailureV1.invalidContext
            }
        }
        try requests.forEach {
            try $0.validate()
            guard $0.workspaceID == expectedWorkspace else {
                throw SearchContractFailureV1.invalidContext
            }
        }
        try actions.forEach {
            try $0.validate()
            guard $0.workspaceID == expectedWorkspace else {
                throw SearchContractFailureV1.invalidContext
            }
        }
        try policies.forEach {
            try $0.validate()
            guard $0.workspaceID == expectedWorkspace else {
                throw SearchContractFailureV1.invalidContext
            }
        }

        let transitionsByReview = Dictionary(grouping: transitions, by: \.reviewID)
        var result: [UUID: InspectionReviewSearchValue] = [:]
        for reviewID in transitionsByReview.keys.sorted(by: {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        }) {
            let reviewTransitions = transitionsByReview[reviewID] ?? []
            let reviewDispositions = dispositions.filter { $0.reviewID == reviewID }
            let reviewRequests = requests.filter { $0.reviewID == reviewID }
            let projection = try InspectionReviewProjectionBuilderV1.rebuild(
                workspaceID: expectedWorkspace,
                reviewID: reviewID,
                transitions: reviewTransitions,
                dispositions: reviewDispositions,
                changeRequests: reviewRequests
            )
            var value = InspectionReviewSearchValue(
                reviewState: projection.state.rawValue,
                timestamp: nil
            )
            for transition in reviewTransitions { value.record(transition.recordedAt) }

            let dispositionHeads = try authorityCriterionUniqueHeadsV1(
                values: reviewDispositions,
                expectedWorkspace: expectedWorkspace,
                id: { $0.dispositionID },
                workspace: { $0.workspaceID },
                predecessor: { $0.supersedesDispositionID },
                group: { $0.reviewID }
            )
            for disposition in dispositionHeads {
                value.dispositions.insert(disposition.kind.rawValue)
                value.record(disposition.recordedAt)
            }

            let requestHeads = try authorityCriterionUniqueHeadsV1(
                values: reviewRequests,
                expectedWorkspace: expectedWorkspace,
                id: { $0.requestRevisionID },
                workspace: { $0.workspaceID },
                predecessor: { $0.supersedesRequestRevisionID },
                group: { $0.requestID }
            )
            for request in requestHeads {
                value.changeStates.insert(request.state.rawValue)
                value.record(request.recordedAt)
            }
            result[reviewID] = value
        }

        // Corrective-action rows name the exact change-request item rather
        // than a review directly. Resolve that immutable item reference to
        // one review; an orphan or ambiguous reference is rejected closed.
        let actionHeads = try authorityCriterionUniqueHeadsV1(
            values: actions,
            expectedWorkspace: expectedWorkspace,
            id: { $0.eventID },
            workspace: { $0.workspaceID },
            predecessor: { $0.predecessorEventID },
            group: { $0.actionID }
        )
        let requestsByReview = Dictionary(grouping: requests, by: \.reviewID)
        for action in actionHeads {
            guard let policy = policies.first(where: {
                guard let reference = try? CorrectiveActionPolicyReferenceV1($0) else {
                    return false
                }
                return reference == action.policy
            }) else {
                throw SearchContractFailureV1.invalidContext
            }
            _ = try CorrectiveActionProjectionBuilderV1.rebuild(
                workspaceID: expectedWorkspace,
                actionID: action.actionID,
                events: actions.filter { $0.actionID == action.actionID },
                policies: [policy],
                now: action.recordedAt
            )
            let candidateReviews = requestsByReview.compactMap { reviewID, values in
                values.contains(where: {
                    let candidate = $0.item.itemID.lowercased()
                    let source = action.source.itemID.lowercased()
                    return candidate == source
                        || $0.requestID.uuidString.lowercased() == source
                        || $0.requestRevisionID.uuidString.lowercased() == source
                }) ? reviewID : nil
            }
            guard candidateReviews.count == 1,
                  let reviewID = candidateReviews.first,
                  var value = result[reviewID] else {
                throw SearchContractFailureV1.invalidContext
            }
            value.actionStates.insert(action.state.rawValue)
            value.record(action.recordedAt)
            result[reviewID] = value
        }

        return try result.keys.sorted(by: {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        }).map { reviewID in
            guard let value = result[reviewID], let timestamp = value.timestamp else {
                throw SearchContractFailureV1.invalidContext
            }
            return CanonicalValue(
                kind: .report,
                stableID: "inspection-review-\(reviewID.uuidString.lowercased())",
                display: "Inspection review",
                summary: "Inspection review",
                breadcrumb: [],
                status: value.reviewState,
                dueAt: nil,
                timestamp: timestamp,
                inspectionReviewStateSummary: value.reviewState,
                inspectionReviewDispositionSummary: value.dispositions.sorted().joined(separator: " "),
                changeRequestStateSummary: value.changeStates.sorted().joined(separator: " "),
                correctiveActionStateSummary: value.actionStates.sorted().joined(separator: " "),
                inspectionReviewProjectionVersionSummary:
                    SearchInspectionReviewPersistencePolicyV1.acceptedProjectionVersionMarkers[1]
            )
        }
    }

    /// Builds one disposable current-head value per packet manifest. Full
    /// claim/lease/release/handoff history is validated by the canonical
    /// projection builder, but only typed state/count metadata is sent to the
    /// search index. Any orphan, fork, stale result, or cross-workspace row
    /// fails the rebuild closed.
    func workPacketSearchValues() throws -> [CanonicalValue] {
        let expectedWorkspace = WorkspaceID(rawValue: workspaceID)
        let manifests = try modelContext.fetch(FetchDescriptor<WorkPacketManifestRow>())
            .filter { $0.workspaceID == workspaceID }
            .map { try $0.value() }
        let claims = try modelContext.fetch(FetchDescriptor<WorkItemClaimRow>())
            .filter { $0.workspaceID == workspaceID }
            .map { try $0.value() }
        let leases = try modelContext.fetch(FetchDescriptor<WorkLeaseRow>())
            .filter { $0.workspaceID == workspaceID }
            .map { try $0.value() }
        let releases = try modelContext.fetch(FetchDescriptor<WorkReleaseRow>())
            .filter { $0.workspaceID == workspaceID }
            .map { try $0.value() }
        let handoffs = try modelContext.fetch(FetchDescriptor<WorkHandoffRow>())
            .filter { $0.workspaceID == workspaceID }
            .map { try $0.value() }
        var identities: Set<UUID> = []
        var packetIdentities: Set<UUID> = []
        let manifestIDs = Set(manifests.map(\.manifestID))
        let packetIDs = Set(manifests.map(\.packetID))
        guard manifestIDs.count == manifests.count,
              packetIDs.count == manifests.count,
              claims.allSatisfy({ manifestIDs.contains($0.manifest.manifestID) }),
              leases.allSatisfy({ packetIDs.contains($0.item.packetID) }),
              releases.allSatisfy({ packetIDs.contains($0.item.packetID) }),
              handoffs.allSatisfy({ packetIDs.contains($0.item.packetID) }) else {
            throw SearchContractFailureV1.invalidContext
        }
        var values: [CanonicalValue] = []
        for manifest in manifests.sorted(by: {
            $0.manifestID.uuidString.lowercased() < $1.manifestID.uuidString.lowercased()
        }) {
            guard identities.insert(manifest.manifestID).inserted,
                  packetIdentities.insert(manifest.packetID).inserted,
                  manifest.workspaceID == expectedWorkspace else {
                throw SearchContractFailureV1.invalidContext
            }
            let manifestReference = try WorkPacketManifestReferenceV1(manifest)
            let itemReferences = try manifest.items.map {
                try WorkPacketItemReferenceV1(manifest: manifest, item: $0)
            }
            let packetClaims = claims.filter {
                $0.manifest.manifestID == manifest.manifestID
            }
            let packetLeases = leases.filter { $0.item.packetID == manifest.packetID }
            let packetReleases = releases.filter { $0.item.packetID == manifest.packetID }
            let packetHandoffs = handoffs.filter { $0.item.packetID == manifest.packetID }
            guard packetClaims.allSatisfy({
                      $0.workspaceID == expectedWorkspace
                          && $0.manifest == manifestReference
                          && itemReferences.contains($0.item)
                  }),
                  packetLeases.allSatisfy({
                      $0.workspaceID == expectedWorkspace
                          && itemReferences.contains($0.item)
                  }),
                  packetReleases.allSatisfy({
                      $0.workspaceID == expectedWorkspace
                          && itemReferences.contains($0.item)
                  }),
                  packetHandoffs.allSatisfy({
                      $0.workspaceID == expectedWorkspace
                          && itemReferences.contains($0.item)
                  }) else {
                throw SearchContractFailureV1.invalidContext
            }
            let timestamp = ([manifest.createdAt]
                + packetClaims.map(\.claimedAt)
                + packetLeases.map(\.startsAt)
                + packetReleases.map(\.releasedAt)
                + packetHandoffs.map(\.handedOffAt)).max() ?? manifest.createdAt
            let projection = try WorkPacketProjectionBuilderV1.rebuild(
                workspaceID: expectedWorkspace,
                manifest: manifest,
                claims: packetClaims,
                leases: packetLeases,
                releases: packetReleases,
                handoffs: packetHandoffs,
                at: timestamp
            )
            let itemSnapshots = try projection.items.map {
                try CompletedWorkPacketItemSnapshotV1(item: $0.item, projection: $0)
            }
            let states = Set(itemSnapshots.map { $0.state.rawValue })
            let hasConflict = itemSnapshots.contains { !$0.conflictKinds.isEmpty }
            values.append(CanonicalValue(
                kind: .work,
                stableID: "work-packet-\(manifest.packetID.uuidString.lowercased())",
                display: "Work packet",
                summary: "Work packet",
                breadcrumb: [],
                status: hasConflict ? "conflicted" : "ready",
                dueAt: nil,
                timestamp: timestamp,
                workPacketManifestStateSummary: hasConflict ? "CONFLICTED" : "READY",
                workPacketItemStateSummary: states.sorted().joined(separator: " "),
                workPacketConflictStateSummary: hasConflict ? "REVIEW_REQUIRED" : "NONE",
                workPacketProjectionVersionSummary:
                    SearchWorkPacketPersistencePolicyV1.acceptedProjectionVersionMarkers[1]
            ))
        }
        return values
    }

    /// Builds only exact activity-bound summaries. Licensed content, clause/raw
    /// locators, external locator values, and derived facts without an explicit
    /// activity reference are intentionally excluded.
    func authorityCriterionSearchValues() throws -> [UUID: AuthorityCriterionSearchValue] {
        let expectedWorkspace = WorkspaceID(rawValue: workspaceID)
        let releases = try modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>())
            .filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        var releaseByID: [UUID: AuthoritySourceReleaseV1] = [:]
        for release in releases {
            guard release.workspaceID == expectedWorkspace,
                  releaseByID[release.releaseID] == nil else {
                throw SearchContractFailureV1.invalidContext
            }
            releaseByID[release.releaseID] = release
        }

        let contexts = try modelContext.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>())
            .filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        var contextByID: [UUID: ApplicabilityContextSnapshotV1] = [:]
        for context in contexts {
            guard context.workspaceID == expectedWorkspace,
                  contextByID[context.snapshotID] == nil else {
                throw SearchContractFailureV1.invalidContext
            }
            contextByID[context.snapshotID] = context
            for basis in context.basisBindings {
                guard basis.workspaceID == expectedWorkspace,
                      let release = releaseByID[basis.authorityReleaseID],
                      release.workspaceID == expectedWorkspace else {
                    throw SearchContractFailureV1.invalidContext
                }
            }
        }
        let currentContexts = try authorityCriterionUniqueHeadsV1(
            values: contexts,
            expectedWorkspace: expectedWorkspace,
            id: { $0.snapshotID },
            workspace: { $0.workspaceID },
            predecessor: { $0.supersedesSnapshotID },
            group: { $0.activityID }
        )
        var currentContextByID: [UUID: ApplicabilityContextSnapshotV1] = [:]
        for context in currentContexts {
            guard currentContextByID[context.snapshotID] == nil else {
                throw SearchContractFailureV1.invalidContext
            }
            currentContextByID[context.snapshotID] = context
        }

        let classifications = try modelContext.fetch(FetchDescriptor<FindingClassificationBindingRow>())
            .filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        var classificationRecords: [AuthorityCriterionClassificationSearchRecordV1] = []
        for classification in classifications {
            guard classification.workspaceID == expectedWorkspace,
                  let context = contextByID[classification.applicabilityContextID],
                  context.workspaceID == expectedWorkspace else {
                throw SearchContractFailureV1.invalidContext
            }
            classificationRecords.append(.init(
                value: classification,
                activityID: context.activityID
            ))
        }
        let currentClassificationRecords = try authorityCriterionUniqueHeadsV1(
            values: classificationRecords,
            expectedWorkspace: expectedWorkspace,
            id: { $0.value.bindingID },
            workspace: { $0.value.workspaceID },
            predecessor: { $0.value.supersedesBindingID },
            group: {
                AuthorityCriterionClassificationChainKeyV1(
                    activityID: $0.activityID,
                    findingID: $0.value.findingID,
                    criterionID: $0.value.criterionID
                )
            }
        )
        var classificationsByContext: [UUID: [FindingClassificationBindingV1]] = [:]
        for record in currentClassificationRecords {
            guard currentContextByID[record.value.applicabilityContextID] != nil else {
                throw SearchContractFailureV1.invalidContext
            }
            classificationsByContext[record.value.applicabilityContextID, default: []]
                .append(record.value)
        }

        var result: [UUID: AuthorityCriterionSearchValue] = [:]
        for context in currentContexts {
            var value = result[context.activityID] ?? AuthorityCriterionSearchValue()
            value.dispositions.insert(context.disposition.rawValue)
            for basis in context.basisBindings {
                guard let release = releaseByID[basis.authorityReleaseID] else {
                    throw SearchContractFailureV1.invalidContext
                }
                value.sources.insert([release.designation, release.editionOrRevision]
                    .joined(separator: " "))
            }
            for classification in classificationsByContext[context.snapshotID] ?? [] {
                value.results.insert("\(classification.criterionID) \(classification.result.rawValue)")
                if let severity = classification.severityLevelID { value.severityLevels.insert(severity) }
            }
            result[context.activityID] = value
        }
        return result
    }

    func stableKey(kind: WorkspaceEntityKindV1, id: UUID) throws -> String {
        try WorkspaceEntityIdentityV1(kind: kind, id: id).stableKey
    }

    func project(
        _ value: CanonicalValue,
        source: SearchSourceRevisionV1
    ) throws -> [SearchIndexProjectionRecordV1] {
        var fields: [(String, String)]
        switch value.kind {
        case .asset:
            if includeFunctionalRelationships,
               value.stableID.hasPrefix("functional-") {
                fields = [
                    ("functional_relationship_descriptor", value.functionalRelationshipDescriptorSummary),
                    ("functional_relationship_direction", value.functionalRelationshipDirectionSummary),
                    ("functional_relationship_state", value.functionalRelationshipStateSummary),
                    ("functional_relationship_endpoint", value.functionalRelationshipEndpointSummary),
                ].filter { !$0.1.isEmpty }
            } else {
                fields = [("asset_identifier", value.stableID), ("asset_label", value.display),
                          ("status", value.status)]
            }
            if includeAssetSemantics && !value.stableID.hasPrefix("functional-") {
                fields += [
                    ("asset_semantic_kind", value.semanticKindSummary),
                    ("asset_semantic_capability", value.semanticCapabilitySummary),
                    ("asset_lifecycle_event", value.lifecycleEventSummary),
                    ("asset_product_identity_state", value.productIdentityStateSummary),
                    ("work_subject_scope", value.workSubjectScopeSummary),
                ].filter { !$0.1.isEmpty }
            }
        case .location:
            fields = [("location_identifier", value.stableID), ("location_label", value.display),
                      ("location_breadcrumb", value.breadcrumb.joined(separator: " ")),
                      ("status", value.status)]
        case .work:
            if includeWorkPacket, value.stableID.hasPrefix("work-packet-") {
                fields = [
                    ("work_packet_identifier", value.stableID),
                    ("work_packet_manifest_state", value.workPacketManifestStateSummary),
                    ("work_packet_item_state", value.workPacketItemStateSummary),
                    ("work_packet_conflict_state", value.workPacketConflictStateSummary),
                    ("work_packet_projection_version", value.workPacketProjectionVersionSummary),
                ].filter { !$0.1.isEmpty }
            } else {
                fields = [("work_identifier", value.stableID), ("work_summary", value.summary),
                          ("status", value.status)]
            }
            if includeAuthorityCriterion, !value.stableID.hasPrefix("work-packet-") {
                fields += [
                    ("authority_source", value.authoritySourceSummary),
                    ("applicability_disposition", value.applicabilityDispositionSummary),
                    ("criterion_result", value.criterionResultSummary),
                    ("severity_level", value.severityLevelSummary),
                    ("measurement_protocol", value.measurementProtocolSummary),
                ].filter { !$0.1.isEmpty }
            }
        case .report:
            if includeInspectionReview, value.stableID.hasPrefix("inspection-review-") {
                fields = [
                    ("inspection_review_state", value.inspectionReviewStateSummary),
                    ("inspection_review_disposition", value.inspectionReviewDispositionSummary),
                    ("change_request_state", value.changeRequestStateSummary),
                    ("corrective_action_state", value.correctiveActionStateSummary),
                    ("inspection_review_projection_version",
                     value.inspectionReviewProjectionVersionSummary),
                ].filter { !$0.1.isEmpty }
            } else if includeAssurance, value.stableID.hasPrefix("assurance-") {
                fields = [
                    ("assurance_audience", value.assuranceAudienceSummary),
                    ("assurance_disposition", value.assuranceDispositionSummary),
                    ("assurance_limitation", value.assuranceLimitationSummary),
                    ("assurance_projection_version", value.assuranceProjectionVersionSummary),
                ].filter { !$0.1.isEmpty }
            } else {
                fields = [("report_identifier", value.stableID), ("report_summary", value.summary),
                          ("status", value.status)]
            }
        case .party:
            fields = [("party_identifier", value.stableID), ("party_label", value.display),
                      ("party_role", value.roleSummary), ("status", value.status)]
        }
        return try fields.map { fieldID, text in
            let searchable = text.isEmpty ? value.stableID : text
            let identity = try SearchCanonicalRecordIdentityV1(
                sourceKind: value.kind,
                stableID: value.stableID
            )
            let operationalSuffix = fieldID == "status"
                && snapshotBackupStaleIdentities.contains(identity)
                ? " backup stale" : ""
            return try SearchIndexProjectionRecordV1(
                workspaceID: workspaceID,
                sourceKind: value.kind,
                sourceStableID: value.stableID,
                sourceRevision: source.commitRevision,
                fieldID: fieldID,
                normalizedTokens: SearchCoordinatorV1.normalizedTokens(
                    searchable + operationalSuffix
                ),
                displayIdentity: value.display,
                locationBreadcrumb: value.breadcrumb,
                status: value.status,
                permittedSnippet: searchable,
                dueAt: value.dueAt,
                sourceTimestamp: value.timestamp
            )
        }
    }

    static func makeRegistry() throws -> SearchableFieldRegistryV1 {
        var fields: [SearchableFieldDescriptorV1] = []
        func append(_ id: String, _ kind: SearchSourceKindV1, identity: Bool = false,
                    operational: Bool = false) throws {
            fields.append(try SearchableFieldDescriptorV1(
                fieldID: id, sourceKind: kind,
                privacyClass: identity ? .userVisibleIdentifier
                    : (operational ? .approvedOperationalState : .approvedCustomerText),
                tokenization: identity ? .exactIdentity : (operational ? .keyword : .unicodeWords),
                normalization: identity ? .stableIdentity : .unicodeCaseAndDiacriticFoldedNFC,
                snippetPermission: (identity || operational)
                    ? .exactDisplayValue : .boundedUserVisibleExcerpt,
                retention: .untilSourceFieldIsAmended, purgeOwner: .indexRebuildCoordinator
            ))
        }
        try append("asset_identifier", .asset, identity: true); try append("asset_label", .asset)
        try append("location_identifier", .location, identity: true); try append("location_label", .location)
        try append("location_breadcrumb", .location)
        try append("work_identifier", .work, identity: true); try append("work_summary", .work)
        try append("report_identifier", .report, identity: true); try append("report_summary", .report)
        // Keep the legacy V1 registry byte-for-byte stable.  The additive
        // party status registration belongs only to the opt-in C38 registry.
        for kind in [.asset, .location, .work, .report] as [SearchSourceKindV1] {
            try append("status", kind, operational: true)
        }
        return try SearchableFieldRegistryV1(fields: fields)
    }

    static func makeAccountabilityRegistry() throws -> SearchableFieldRegistryV1 {
        var fields: [SearchableFieldDescriptorV1] = []
        func append(_ id: String, _ kind: SearchSourceKindV1, identity: Bool = false,
                    operational: Bool = false) throws {
            fields.append(try SearchableFieldDescriptorV1(
                fieldID: id, sourceKind: kind,
                privacyClass: identity ? .userVisibleIdentifier
                    : (operational ? .approvedOperationalState : .approvedCustomerText),
                tokenization: identity ? .exactIdentity : (operational ? .keyword : .unicodeWords),
                normalization: identity ? .stableIdentity : .unicodeCaseAndDiacriticFoldedNFC,
                snippetPermission: (identity || operational)
                    ? .exactDisplayValue : .boundedUserVisibleExcerpt,
                retention: .untilSourceFieldIsAmended, purgeOwner: .indexRebuildCoordinator
            ))
        }
        try append("asset_identifier", .asset, identity: true)
        try append("asset_label", .asset)
        try append("location_identifier", .location, identity: true)
        try append("location_label", .location)
        try append("location_breadcrumb", .location)
        try append("work_identifier", .work, identity: true)
        try append("work_summary", .work)
        try append("report_identifier", .report, identity: true)
        try append("report_summary", .report)
        try append("party_identifier", .party, identity: true)
        try append("party_label", .party)
        try append("party_role", .party)
        for kind in [.asset, .location, .work, .report, .party] as [SearchSourceKindV1] {
            try append("status", kind, operational: true)
        }
        return try SearchableFieldRegistryV1(fields: fields)
    }

    static func makeAssetSemanticsRegistry(
        includeAccountability: Bool,
        includeInspectionReview: Bool = false
    ) throws -> SearchableFieldRegistryV1 {
        try makeExtendedRegistry(
            includeAccountability: includeAccountability || includeInspectionReview,
            includeAssetSemantics: true,
            includeAuthorityCriterion: includeInspectionReview,
            includeFunctionalRelationships: includeInspectionReview,
            includeAssurance: includeInspectionReview,
            includeInspectionReview: includeInspectionReview
        )
    }

    static func makeEvidenceAssuranceRegistry(
        includeAccountability: Bool = false,
        includeAssetSemantics: Bool = false,
        includeAuthorityCriterion: Bool = false,
        includeFunctionalRelationships: Bool = false,
        includeInspectionReview: Bool = false
    ) throws -> SearchableFieldRegistryV1 {
        try makeExtendedRegistry(
            includeAccountability: includeAccountability || includeInspectionReview,
            includeAssetSemantics: includeAssetSemantics || includeInspectionReview,
            includeAuthorityCriterion: includeAuthorityCriterion || includeInspectionReview,
            includeFunctionalRelationships: includeFunctionalRelationships || includeInspectionReview,
            includeAssurance: true,
            includeInspectionReview: includeInspectionReview
        )
    }

    static func makeFunctionalRelationshipsRegistry(
        includeAccountability: Bool = false,
        includeAssetSemantics: Bool = false,
        includeAuthorityCriterion: Bool = false,
        includeAssurance: Bool = false,
        includeInspectionReview: Bool = false
    ) throws -> SearchableFieldRegistryV1 {
        try makeExtendedRegistry(
            includeAccountability: includeAccountability || includeInspectionReview,
            includeAssetSemantics: includeAssetSemantics || includeInspectionReview,
            includeAuthorityCriterion: includeAuthorityCriterion || includeInspectionReview,
            includeFunctionalRelationships: true,
            includeAssurance: includeAssurance || includeInspectionReview,
            includeInspectionReview: includeInspectionReview
        )
    }

    static func makeInspectionReviewRegistry() throws -> SearchableFieldRegistryV1 {
        try makeExtendedRegistry(
            includeAccountability: true,
            includeAssetSemantics: true,
            includeAuthorityCriterion: true,
            includeFunctionalRelationships: true,
            includeAssurance: true,
            includeInspectionReview: true
        )
    }

    static func makeWorkPacketRegistry() throws -> SearchableFieldRegistryV1 {
        try makeExtendedRegistry(
            includeAccountability: true,
            includeAssetSemantics: true,
            includeAuthorityCriterion: true,
            includeFunctionalRelationships: true,
            includeAssurance: true,
            includeInspectionReview: true,
            includeWorkPacket: true
        )
    }

    static func makeExtendedRegistry(
        includeAccountability: Bool,
        includeAssetSemantics: Bool,
        includeAuthorityCriterion: Bool,
        includeFunctionalRelationships: Bool = false,
        includeAssurance: Bool = false,
        includeInspectionReview: Bool = false,
        includeWorkPacket: Bool = false
    ) throws -> SearchableFieldRegistryV1 {
        let resolvedInspectionReview = includeInspectionReview || includeWorkPacket
        let resolvedAccountability = includeAccountability || resolvedInspectionReview
        let resolvedAssetSemantics = includeAssetSemantics || resolvedInspectionReview
        let resolvedAuthorityCriterion = includeAuthorityCriterion || resolvedInspectionReview
        let resolvedFunctionalRelationships = includeFunctionalRelationships || resolvedInspectionReview
        let resolvedAssurance = includeAssurance || resolvedInspectionReview
        var fields = try (resolvedAccountability ? makeAccountabilityRegistry() : makeRegistry()).fields
        func append(_ id: String, _ kind: SearchSourceKindV1) throws {
            let identity = id == FrozenSearchableFieldV1.workPacketIdentifier.rawValue
            fields.append(try SearchableFieldDescriptorV1(
                fieldID: id,
                sourceKind: kind,
                privacyClass: identity
                    ? .userVisibleIdentifier : .approvedCustomerText,
                tokenization: identity ? .exactIdentity : .unicodeWords,
                normalization: identity
                    ? .stableIdentity : .unicodeCaseAndDiacriticFoldedNFC,
                snippetPermission: identity
                    ? .exactDisplayValue : .boundedUserVisibleExcerpt,
                retention: .untilSourceFieldIsAmended,
                purgeOwner: .indexRebuildCoordinator
            ))
        }
        if resolvedAssetSemantics {
            for id in SearchAssetSemanticsPersistencePolicyV1.fieldIDs { try append(id, .asset) }
        }
        if resolvedAuthorityCriterion {
            for id in SearchAuthorityCriterionPersistencePolicyV1.fieldIDs { try append(id, .work) }
        }
        if resolvedFunctionalRelationships {
            for id in SearchFunctionalRelationshipsPersistencePolicyV1.fieldIDs {
                try append(id, .asset)
            }
        }
        if resolvedAssurance {
            for id in SearchEvidenceAssurancePersistencePolicyV1.fieldIDs {
                try append(id, .report)
            }
        }
        if resolvedInspectionReview {
            for id in SearchInspectionReviewPersistencePolicyV1.fieldIDs {
                try append(id, .report)
            }
        }
        if includeWorkPacket {
            for id in SearchWorkPacketPersistencePolicyV1.fieldIDs {
                try append(id, .work)
            }
        }
        return try SearchableFieldRegistryV1(fields: fields)
    }
}

enum SearchIndexRebuildFailureV1: Error, Equatable, Sendable {
    case sourceChangedDuringRebuild
    case invalidPage
    case recordLimitExceeded
}

struct PrivateSystemDiscoveryProductionRebuildSourceV1: PrivateSystemDiscoveryRebuildRequestProvidingV1 {
    private let optIn: @Sendable () async throws -> PrivateSystemDiscoveryOptInV1
    private let protectedDataAvailable: @Sendable () async -> Bool
    private let now: @Sendable () -> Date

    init(
        optIn: @escaping @Sendable () async throws -> PrivateSystemDiscoveryOptInV1 = {
            try PreferencesAdapterV1().readPrivateSystemDiscoveryOptIn()
        },
        protectedDataAvailable: @escaping @Sendable () async -> Bool = {
            await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.optIn = optIn
        self.protectedDataAvailable = protectedDataAvailable
        self.now = now
    }

    func privateSystemDiscoveryRebuildRequest(
        source: SearchSourceRevisionV1,
        operationID: PrivateSystemDiscoveryOperationIDV1
    ) async throws -> PrivateSystemDiscoveryIndexRebuildPayloadV1? {
        try operationID.validate()
        let workspaceID = WorkspaceID(rawValue: source.workspaceID)
        guard operationID.operation == .rebuild,
              operationID.workspaceID == workspaceID else {
            throw PrivateSystemDiscoveryFailureV1.invalidValue
        }
        let manifest = try PrivateSystemDiscoveryManifestV1()
        let setting = try await optIn()
        let requestedAt = now()
        let protected = await protectedDataAvailable()
        let availability = try PrivateSystemDiscoveryActionV1.allCases.map {
            try AppIntentAvailabilityV1(
                workspaceID: workspaceID, action: $0,
                optedIn: setting.contains(workspaceID),
                featureReason: setting.contains(workspaceID) ? .available : .workspacePolicyDisabled,
                appAccessPermitsContent: setting.contains(workspaceID),
                protectedDataAvailable: protected, evaluatedAt: requestedAt
            )
        }
        let descriptors = try PrivateSystemDiscoveryProjectionDomainV1.allCases.map {
            try PrivateSystemDiscoveryProjectionDescriptorV1(
                domain: $0, projectionVersion: 1,
                allowlistSHA256: manifest.manifestSHA256,
                policySHA256: manifest.manifestSHA256,
                indexDefinitionSHA256: manifest.manifestSHA256
            )
        }.sorted { $0.stableKey < $1.stableKey }
        let request = try PrivateSystemDiscoveryRebuildRequestV1(
            operationRawID: operationID.rawValue, workspaceID: workspaceID,
            workspaceRevision: source.commitRevision, deletionFrontier: 0,
            sourceStateSHA256: operationID.inputSHA256, requestedAt: requestedAt
        )
        return PrivateSystemDiscoveryIndexRebuildPayloadV1(
            request: request, descriptors: descriptors, manifest: manifest,
            optIn: setting, availability: availability, requestedAt: requestedAt
        )
    }
}

struct SearchIndexRebuildResultV1: Equatable, Sendable {
    let disposition: SearchIndexReconciliationV1
    let source: SearchSourceRevisionV1
    let indexedRecordCount: Int
    let resumedFromCheckpoint: Bool
}

/// Rebuilds into durable staging pages and publishes only after the source
/// revision is re-read and proven unchanged. Cancellation retains the last
/// complete checkpoint; storage failures never replace a complete index.
actor SearchIndexRebuildCoordinatorV1 {
    static let pageSize = 250
    static let maximumCanonicalRecords = SearchContractLimitsV1.maximumCanonicalRecords
    static let maximumProjectionRowsPerPage = pageSize
        * SearchContractLimitsV1.maximumSearchableFieldCount

    private let store: LocalSearchIndexStoreV1
    private let source: any SearchCanonicalProjectionSourceV1
    private let registry: SearchableFieldRegistryV1
    private let makeOperationID: @Sendable () -> UUID
    private let privateSystemDiscoveryIndex: (any PrivateSystemDiscoveryIndexLifecyclePortV1)?
    private let privateSystemDiscoverySource: (any PrivateSystemDiscoveryRebuildRequestProvidingV1)?

    init(
        store: LocalSearchIndexStoreV1,
        source: any SearchCanonicalProjectionSourceV1,
        registry: SearchableFieldRegistryV1,
        makeOperationID: @escaping @Sendable () -> UUID = { UUID() },
        privateSystemDiscoveryIndex: (any PrivateSystemDiscoveryIndexLifecyclePortV1)? = PrivateSystemDiscoveryIndexRuntimeV1.shared,
        privateSystemDiscoverySource: (any PrivateSystemDiscoveryRebuildRequestProvidingV1)? = PrivateSystemDiscoveryProductionRebuildSourceV1()
    ) throws {
        try registry.validate()
        guard C08ImportBulkSearchRebuildBoundaryV1.validate(),
              C08ImportBulkLocalSearchIndexBoundaryV1.validate() else {
            throw SearchIndexRebuildFailureV1.recordLimitExceeded
        }
        self.store = store
        self.source = source
        self.registry = registry
        self.makeOperationID = makeOperationID
        self.privateSystemDiscoveryIndex = privateSystemDiscoveryIndex
        self.privateSystemDiscoverySource = privateSystemDiscoverySource
    }

    func rebuildIfNeeded() async throws -> SearchIndexRebuildResultV1 {
        do {
            return try await performRebuildIfNeeded()
        } catch {
            await source.discardCachedSearchProjectionSnapshot()
            throw error
        }
    }

    func rebuildIfNeeded(
        accessGate: any AppAccessGatePortV1
    ) async throws -> SearchIndexRebuildResultV1 {
        _ = try await accessGate.requireContentAccess(for: .searchRebuild)
        return try await rebuildIfNeeded()
    }

    private func performRebuildIfNeeded() async throws -> SearchIndexRebuildResultV1 {
        try Task.checkCancellation()
        let target = try await source.currentSearchSourceRevision()
        let existingRevision = try await store.revision()
        let disposition = SearchIndexReconciliationV1.disposition(
            source: target,
            index: existingRevision
        )
        if disposition == .current {
            let projection = try await store.projection(for: target, registry: registry)
            try await rebuildPrivateSystemDiscovery(source: target, operationRawID: nil)
            return SearchIndexRebuildResultV1(
                disposition: disposition,
                source: target,
                indexedRecordCount: projection.records.count,
                resumedFromCheckpoint: false
            )
        }

        switch disposition {
        case .staleDropAndRebuild, .aheadDropAndRebuild,
             .incompatibleFormatDropAndRebuild, .wrongGenerationDropAndRebuild:
            // A complete projection that is not current must not survive into
            // publication. In particular, an ahead watermark would otherwise
            // cause replaceProjection to reject the revision-bound rebuild.
            try await store.dropProjection()
        case .absentBuild:
            break
        case .current:
            preconditionFailure("Handled above")
        }
        let publicationToken = await store.publicationToken()

        var staging = try await store.rebuildStaging(publicationToken: publicationToken)
        let canResume = staging.map {
            $0.checkpoint.source == target
                && $0.checkpoint.projectionFormatVersion
                    == SearchPersistenceReleaseV1.derivedProjectionFormatVersion
                && $0.checkpoint.state == .building
        } ?? false
        if !canResume {
            if staging != nil {
                try await store.clearRebuildStaging(
                    publicationToken: publicationToken
                )
            }
            let operationID = makeOperationID()
            guard operationID != SearchContractValidationV1.zeroUUID else {
                throw SearchContractFailureV1.invalidRevision
            }
            let checkpoint = try SearchIndexRebuildCheckpointV1(
                operationID: operationID,
                source: target,
                nextCanonicalOffset: 0,
                projectedRecordCount: 0,
                state: .building
            )
            try await store.saveRebuildStaging(
                checkpoint: checkpoint,
                records: [],
                registry: registry,
                publicationToken: publicationToken
            )
            staging = SearchIndexRebuildStagingV1(checkpoint: checkpoint, records: [])
        }

        guard var active = staging else { throw SearchIndexRebuildFailureV1.invalidPage }
        let resumed = canResume && active.checkpoint.nextCanonicalOffset > 0
        var records = active.records
        var offset = active.checkpoint.nextCanonicalOffset
        var isComplete = false

        while !isComplete {
            try Task.checkCancellation()
            let page = try await source.searchProjectionPage(
                at: target,
                canonicalOffset: offset,
                limit: Self.pageSize
            )
            guard page.requestedCanonicalOffset == offset,
                  page.nextCanonicalOffset >= offset,
                  page.nextCanonicalOffset - offset <= Self.pageSize,
                  (page.records.isEmpty || page.nextCanonicalOffset > offset),
                  (page.isComplete || page.nextCanonicalOffset > offset),
                  page.nextCanonicalOffset <= Self.maximumCanonicalRecords,
                  page.records.allSatisfy({
                    $0.workspaceID == target.workspaceID
                        && $0.sourceRevision <= target.commitRevision
                  }) else {
                throw SearchIndexRebuildFailureV1.invalidPage
            }
            let projectionRowCapacity = Self.maximumCanonicalRecords
                * registry.fields.count
            if records.count + page.records.count > projectionRowCapacity {
                throw SearchIndexRebuildFailureV1.recordLimitExceeded
            }

            records.append(contentsOf: page.records)
            records = try SearchIndexProjectionRecordV1.validateProjection(records, against: registry)
            offset = page.nextCanonicalOffset
            isComplete = page.isComplete
            let checkpoint = try SearchIndexRebuildCheckpointV1(
                operationID: active.checkpoint.operationID,
                source: target,
                nextCanonicalOffset: offset,
                projectedRecordCount: records.count,
                state: .building
            )
            try await store.saveRebuildStaging(
                checkpoint: checkpoint,
                records: records,
                registry: registry,
                publicationToken: publicationToken
            )
            active = SearchIndexRebuildStagingV1(checkpoint: checkpoint, records: records)
        }

        try Task.checkCancellation()
        let finalSource = try await source.currentSearchSourceRevision()
        guard finalSource == target else {
            throw SearchIndexRebuildFailureV1.sourceChangedDuringRebuild
        }
        try Task.checkCancellation()
        try await store.replaceProjection(
            source: target,
            records: records,
            registry: registry,
            publicationToken: publicationToken
        )
        try await rebuildPrivateSystemDiscovery(
            source: target, operationRawID: active.checkpoint.operationID
        )
        return SearchIndexRebuildResultV1(
            disposition: disposition,
            source: target,
            indexedRecordCount: records.count,
            resumedFromCheckpoint: resumed
        )
    }

    private func rebuildPrivateSystemDiscovery(
        source: SearchSourceRevisionV1,
        operationRawID: UUID?
    ) async throws {
        guard let privateSystemDiscoveryIndex, let privateSystemDiscoverySource else { return }
        let inputSHA256 = CompatibilityCanonicalV1.sha256(
            try CompatibilityCanonicalV1.encode(source)
        )
        let rawID: UUID
        if let operationRawID { rawID = operationRawID }
        else { rawID = try deterministicDiscoveryOperationID(inputSHA256: inputSHA256) }
        let operationID = try PrivateSystemDiscoveryOperationIDV1(
            rawValue: rawID, operation: .rebuild,
            workspaceID: WorkspaceID(rawValue: source.workspaceID),
            inputSHA256: inputSHA256
        )
        guard let payload = try await privateSystemDiscoverySource
            .privateSystemDiscoveryRebuildRequest(source: source, operationID: operationID) else { return }
        try await PrivateSystemDiscoverySearchRebuildBoundaryV1.rebuild(
            operationID: payload.request.operationID, index: privateSystemDiscoveryIndex,
            workspaceID: payload.request.workspaceID,
            workspaceRevision: payload.request.workspaceRevision,
            deletionFrontier: payload.request.deletionFrontier,
            descriptors: payload.descriptors, manifest: payload.manifest,
            optIn: payload.optIn, availability: payload.availability,
            now: payload.requestedAt
        )
    }

    private func deterministicDiscoveryOperationID(inputSHA256: String) throws -> UUID {
        let digest = CompatibilityCanonicalV1.sha256(
            Data(("PRIVATE_SYSTEM_DISCOVERY_REBUILD_V1|" + inputSHA256).utf8)
        )
        let compact = String(digest.prefix(32))
        let uuidText = "\(compact.prefix(8))-\(compact.dropFirst(8).prefix(4))-\(compact.dropFirst(12).prefix(4))-\(compact.dropFirst(16).prefix(4))-\(compact.dropFirst(20).prefix(12))"
        guard let value = UUID(uuidString: uuidText) else {
            throw PrivateSystemDiscoveryFailureV1.corruptDigest
        }
        return value
    }

    func cancelAndRetainCheckpoint() {
        // Cooperative cancellation belongs to the calling Task. Staging is
        // already durable after every page, so no write is required here.
    }

    func dropAndRebuild() async throws -> SearchIndexRebuildResultV1 {
        try await store.dropProjection()
        return try await rebuildIfNeeded()
    }

    func purgeWorkspace(_ workspaceID: UUID) async throws {
        try await store.purgeWorkspace(workspaceID)
    }

    func eraseAll() async throws {
        try await store.eraseAll()
    }
}

@MainActor
struct ProductionSearchServicesV1 {
    let source: SwiftDataSearchCanonicalProjectionSourceV1
    let registry: SearchableFieldRegistryV1
    let searchCoordinator: SearchCoordinatorV1
    let rebuildCoordinator: SearchIndexRebuildCoordinatorV1

    init(
        store: LocalSearchIndexStoreV1,
        modelContext: ModelContext,
        workspaceID: UUID,
        generationID: UUID,
        revisionProvider: @escaping @MainActor () throws -> SearchSourceRevisionV1,
        operationalStatusProvider: (any SearchOperationalStatusProvidingV1)? = nil,
        includeAccountability: Bool = false,
        includeAssetSemantics: Bool = true,
        includeAuthorityCriterion: Bool = true,
        includeFunctionalRelationships: Bool = false,
        includeAssurance: Bool = false,
        includeInspectionReview: Bool = false
    ) throws {
        let source = try SwiftDataSearchCanonicalProjectionSourceV1(
            modelContext: modelContext,
            workspaceID: workspaceID,
            generationID: generationID,
            revisionProvider: revisionProvider,
            operationalStatusProvider: operationalStatusProvider,
            includeAccountability: includeAccountability,
            includeAssetSemantics: includeAssetSemantics,
            includeAuthorityCriterion: includeAuthorityCriterion,
            includeFunctionalRelationships: includeFunctionalRelationships,
            includeAssurance: includeAssurance,
            includeInspectionReview: includeInspectionReview
        )
        self.source = source
        registry = source.registry
        searchCoordinator = SearchCoordinatorV1(index: store)
        rebuildCoordinator = try SearchIndexRebuildCoordinatorV1(
            store: store,
            source: source,
            registry: source.registry
        )
    }
}

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds only the bounded package-evolution search projection from the
    /// canonical lifecycle closure. Search never replays package bytes,
    /// payloads, actor identity, or exact candidate heads.
    static func packageEvolutionSearchRecords(
        from closure: PackageEvolutionLifecycleClosureV1
    ) throws -> [PackageEvolutionSearchRecordV1] {
        try closure.validate()
        let releases = Dictionary(uniqueKeysWithValues: closure.promotedReleases.map {
            ($0.releaseRecordID, $0)
        })
        let runs = Dictionary(uniqueKeysWithValues: closure.sandboxRuns.map { ($0.runID, $0) })
        let pointers = Dictionary(uniqueKeysWithValues: closure.activePointers.map {
            ($0.pointerSHA256, $0)
        })
        return try closure.promotionReceipts.map { receipt in
            guard let release = releases[receipt.promotedReleaseRecordID],
                  let run = runs[receipt.sandboxRunID],
                  let pointer = pointers[receipt.resultingPointerSHA256] else {
                throw PackageEvolutionConsumerFailureV1.mismatchedRelease
            }
            let predecessor = receipt.predecessorPointerSHA256
                == String(repeating: "0", count: 64)
                ? nil
                : pointers[receipt.predecessorPointerSHA256]
            let bundle = PackagePromotionAtomicBundleV1(
                promotedRelease: release,
                sandboxRun: run,
                semanticDiff: receipt.semanticDiff,
                predecessorPointer: predecessor,
                resultingPointer: pointer,
                actor: receipt.declaredActor,
                receipt: receipt
            )
            return try PackageEvolutionSearchRecordV1(
                metadata: PackageEvolutionConsumerMetadataV1(bundle: bundle)
            )
        }.sorted {
            if $0.packageID != $1.packageID { return $0.packageID < $1.packageID }
            return $0.packageReleaseID < $1.packageReleaseID
        }
    }

    static let packageEvolutionReplayDisposition =
        "REBUILD_FROM_CANONICAL_PACKAGE_PROMOTION_RECEIPT"

    /// Rebuilds the C19 disposable metadata rows from frozen report
    /// projections. Sorting and duplicate rejection make replay deterministic;
    /// exact values and private provenance never enter the searchable rows.
    static func measurementIntegritySearchRecords(
        from projections: [MeasurementIntegrityReportProjectionV1],
        sourceRevision: UInt64 = 0
    ) throws -> [MeasurementIntegritySearchRecordV1] {
        let records = try projections.map {
            try MeasurementIntegritySearchRecordV1(
                projection: $0,
                sourceRevision: sourceRevision
            )
        }.sorted { lhs, rhs in
            lhs.captureID.uuidString.lowercased() < rhs.captureID.uuidString.lowercased()
        }
        guard Set(records.map(\.captureID)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try $0.validate() }
        return records
    }

    static let measurementIntegrityReplayDisposition =
        "DROP_AND_REBUILD_FROM_FROZEN_MEASUREMENT_PROJECTION"

    /// C20 replay reconstructs disposable rows from the approved derivative
    /// projection, never from original/derivative bytes or review payloads.
    static func privacyTransformSearchRecords(
        from projections: [PrivacyTransformReportProjectionV1]
    ) throws -> [PrivacyTransformSearchRecordV1] {
        try PrivacyTransformSearchPersistencePolicyV1().validate()
        let records = try projections.map {
            try PrivacyTransformSearchRecordV1(projection: $0)
        }.sorted {
            $0.manifestID.uuidString.lowercased() < $1.manifestID.uuidString.lowercased()
        }
        guard Set(records.map(\.manifestID)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try $0.validate() }
        return records
    }

    static let privacyTransformReplayDisposition =
        "DROP_AND_REBUILD_FROM_APPROVED_PRIVACY_DERIVATIVE_PROJECTION"

    /// C21 search replay consumes canonical admission decisions and emits
    /// disposable metadata rows. It never replays package payloads or tries
    /// to infer a missing client/device identity.
    static func clientCapabilitySearchRecords(
        from projections: [ClientCapabilityReportProjectionV1]
    ) throws -> [ClientCapabilitySearchRecordV1] {
        try ClientCapabilitySearchPersistencePolicyV1().validate()
        let records = try projections.map {
            try ClientCapabilitySearchRecordV1(projection: $0)
        }.sorted {
            $0.decisionID.uuidString.lowercased() < $1.decisionID.uuidString.lowercased()
        }
        guard Set(records.map(\.decisionID)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try $0.validate() }
        return records
    }

    static let clientCapabilityReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_CLIENT_CAPABILITY_DECISION"

    /// Rebuilds the C23 disposable search rows from immutable report
    /// projections. No replay path consults a current pointer or reference
    /// content store.
    static func fieldReferenceSearchRecords(
        from projections: [FieldReferenceReportProjectionV1]
    ) throws -> [FieldReferenceSearchRecordV1] {
        try FieldReferenceSearchPersistencePolicyV1().validate()
        let records = try projections.map {
            try FieldReferenceSearchRecordV1(projection: $0)
        }.sorted {
            $0.projectionSHA256 < $1.projectionSHA256
        }
        guard Set(records.map(\.projectionSHA256)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try $0.validate() }
        return records
    }

    static let fieldReferenceReplayDisposition =
        "DROP_AND_REBUILD_FROM_FROZEN_FIELD_REFERENCE_BINDING"
}

extension SearchIndexRebuildCoordinatorV1 {
    static func advancedScheduleOccurrenceSearchRecords(
        from projections: [AdvancedScheduleReportProjectionV1]
    ) throws -> [AdvancedScheduleOccurrenceSearchRecordV1] {
        try AdvancedScheduleOccurrenceSearchPersistencePolicyV1().validate()
        guard projections.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        var values: [AdvancedScheduleOccurrenceSearchRecordV1] = []
        for projection in projections.sorted(by: { $0.projectionSHA256 < $1.projectionSHA256 }) {
            try projection.validate()
            for occurrence in projection.occurrences {
                values.append(try LocalSearchIndexStoreV1.advancedScheduleOccurrenceSearchRecord(
                    from: projection, occurrence: occurrence))
            }
        }
        values.sort { $0.projectionIdentity < $1.projectionIdentity }
        guard values.count <= SearchContractLimitsV1.maximumProjectionRecords,
              Set(values.map(\.projectionIdentity)).count == values.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        return values
    }
    static let advancedScheduleRebuildParityRequired = true
}

// MARK: - C30 operating-context rebuild

extension SearchIndexRebuildCoordinatorV1 {
    static func rebuildOperatingContextRecords(
        from projections: [C30EvidenceContextReportReferenceV1]
    ) throws -> [C30OperatingContextSearchRecordV1] {
        try C30OperatingContextSearchPersistencePolicyV1.validate()
        let records = try projections.map {
            try LocalSearchIndexStoreV1.operatingContextSearchRecord(from: $0)
        }.sorted {
            ($0.evidenceID, $0.contextRevision) < ($1.evidenceID, $1.contextRevision)
        }
        guard Set(records.map(\.contextID)).count == records.count,
              records.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try C30OperatingContextSearchPolicyV1.validate($0) }
        return records
    }

    static let c30OperatingContextRestoreDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_CONTEXT"
    static let c30OperatingContextReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_CONTEXT"
}

// MARK: - C24 accessible-document search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds disposable C24 rows from canonical semantic trees.  The
    /// ordering is digest-based and assessment matching is transient; no
    /// semantic tree or evidence payload is persisted in the index.
    static func accessibleDocumentSearchRecords(
        from trees: [AccessibleDocumentSemanticTreeV1],
        assessments: [AccessibleDocumentAssessmentReceiptV1] = []
    ) throws -> [AccessibleDocumentSearchRecordV1] {
        try AccessibleDocumentSearchPersistencePolicyV1().validate()
        guard trees.count <= AccessibleDocumentSearchRecordV1.maximumValues,
              assessments.count <= AccessibleDocumentSearchRecordV1.maximumValues else {
            throw SearchContractFailureV1.limitExceeded
        }
        let grouped = Dictionary(grouping: assessments, by: \.treeSHA256)
        guard grouped.values.allSatisfy({ $0.count <= 1 }) else {
            throw SearchContractFailureV1.duplicateProjection
        }
        let records = try trees.map { tree in
            try AccessibleDocumentSearchRecordV1(
                tree: tree,
                assessment: grouped[tree.treeSHA256]?.first
            )
        }.sorted { $0.treeSHA256 < $1.treeSHA256 }
        guard Set(records.map(\.treeSHA256)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try $0.validate() }
        return records
    }

    static let accessibleDocumentReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_ACCESSIBLE_DOCUMENT_TREE"
}

// MARK: - C25 survey-definition search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds the disposable survey-definition index from immutable release
    /// facts and the canonical identity's recorded lifecycle state.  A
    /// missing state is rejected rather than inferred, and no draft answer,
    /// prompt, locator, or actor value is accepted by this consumer.
    static func surveyDefinitionSearchRecords(
        from releases: [SurveyDefinitionReleaseV1],
        identities: [SurveyDefinitionIdentityV1]
    ) throws -> [SurveyDefinitionSearchRecordV1] {
        try SurveyDefinitionSearchPersistencePolicyV1().validate()
        guard releases.count <= 4_096, identities.count <= 4_096 else {
            throw SurveyDefinitionConsumerFailureV1.limitExceeded
        }
        try releases.forEach { try $0.validate() }
        try identities.forEach { try $0.validateIntrinsic() }

        let sortedReleases = releases.sorted {
            $0.releaseID.uuidString.lowercased() < $1.releaseID.uuidString.lowercased()
        }
        let sortedIdentities = identities.sorted {
            $0.definitionID.uuidString.lowercased() < $1.definitionID.uuidString.lowercased()
        }
        guard Set(sortedReleases.map(\.releaseID)).count == sortedReleases.count,
              Set(sortedIdentities.map(\.definitionID)).count == sortedIdentities.count else {
            throw SurveyDefinitionConsumerFailureV1.duplicateIdentity
        }

        let releasesByID = Dictionary(uniqueKeysWithValues: sortedReleases.map { ($0.releaseID, $0) })
        let records = try sortedIdentities.map { identity in
            guard let release = releasesByID[identity.currentRelease.releaseID],
                  release.workspaceID == identity.workspaceID,
                  release.definitionID == identity.definitionID,
                  release.activityKind == identity.activityKind,
                  identity.currentRelease == (try SurveyDefinitionReleaseReferenceV1(release)) else {
                throw SurveyDefinitionConsumerFailureV1.staleBinding
            }
            return try LocalSearchIndexStoreV1.surveyDefinitionSearchRecord(
                from: release,
                lifecycleState: identity.lifecycleState
            )
        }
        return records.sorted { $0.releaseID < $1.releaseID }
    }

    /// Binds the C20 derived library to the same current-tip rebuild without
    /// admitting favorite/recent overlay values into search rows.
    static func surveyDefinitionSearchRecords(
        from releases: [SurveyDefinitionReleaseV1],
        libraryRows: [SurveyDefinitionLibraryRowV1],
        authoringPolicy: SurveyAuthoringPolicyV1
    ) throws -> [SurveyDefinitionSearchRecordV1] {
        try authoringPolicy.validate()
        guard libraryRows.count <= 4_096,
              Set(libraryRows.map { $0.identity.definitionID }).count == libraryRows.count else {
            throw SurveyDefinitionConsumerFailureV1.duplicateIdentity
        }
        try libraryRows.forEach { row in
            try row.identity.validateIntrinsic()
            try row.release.validate()
            guard row.identity.currentRelease == row.release,
                  row.identity.lifecycleState == row.lifecycleState else {
                throw SurveyDefinitionConsumerFailureV1.staleBinding
            }
        }
        return try surveyDefinitionSearchRecords(
            from: releases,
            identities: libraryRows.map(\.identity)
        )
    }

    /// Compatibility entry point retained for source compatibility. A state
    /// map cannot prove which immutable release is current, so any nonempty
    /// request fails closed and must use the identity-bound overload above.
    static func surveyDefinitionSearchRecords(
        from releases: [SurveyDefinitionReleaseV1],
        lifecycleStates: [UUID: SurveyDefinitionLifecycleStateV1]
    ) throws -> [SurveyDefinitionSearchRecordV1] {
        try SurveyDefinitionSearchPersistencePolicyV1().validate()
        guard releases.count <= 4_096 else {
            throw SurveyDefinitionConsumerFailureV1.limitExceeded
        }
        guard releases.isEmpty, lifecycleStates.isEmpty else {
            throw SurveyDefinitionConsumerFailureV1.staleBinding
        }
        return []
    }

    static let surveyDefinitionReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_SURVEY_DEFINITION_IDENTITY_TIPS"
    static let surveyDefinitionRestoreDisposition =
        "EXCLUDE_INDEX_ROWS_AND_REBUILD_AFTER_CANONICAL_RESTORE"
}

// MARK: - C26 guided-survey session search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds disposable session rows from validated canonical snapshots.
    /// Only IDs, closed state values, revisions, and a bounded fact count are
    /// retained; answer payloads, prompts, labels, actors, and evidence are
    /// intentionally consumed transiently and never become index data.
    static func surveySessionSearchRecords(
        from sessions: [SurveySessionV1],
        publications: [SurveyPublicationSnapshotV1] = [],
        provisionalSubjects: [ProvisionalSubjectV1] = [],
        factStates: [UUID: SurveySessionFactLocalizationStateV1] = [:],
        publicationStates: [UUID: SurveySessionPublicationLocalizationStateV1] = [:]
    ) throws -> [SurveySessionSearchRecordV1] {
        try SurveySessionSearchPersistencePolicyV1().validate()
        guard sessions.count <= 4_096,
              publications.count <= 4_096,
              provisionalSubjects.count <= 4_096 else {
            throw SearchContractFailureV1.limitExceeded
        }

        try sessions.forEach { try $0.validateIntrinsic() }
        let sessionsByID = Dictionary(grouping: sessions, by: \.sessionID)
        let orderedSessions = try sessionsByID.values.map { history -> SurveySessionV1 in
            let ordered = history.sorted {
                if $0.revision != $1.revision { return $0.revision < $1.revision }
                return $0.sessionSHA256 < $1.sessionSHA256
            }
            guard Set(ordered.map(\.revision)).count == ordered.count,
                  Set(ordered.map(\.sessionSHA256)).count == ordered.count,
                  let current = ordered.last else {
                throw SearchContractFailureV1.duplicateProjection
            }
            if ordered.count > 1 {
                for (prior, successor) in zip(ordered, ordered.dropFirst()) {
                    guard successor.workspaceID == prior.workspaceID,
                          successor.sessionID == prior.sessionID,
                          successor.authority == prior.authority,
                          successor.activityKind == prior.activityKind,
                          successor.subject == prior.subject,
                          successor.startedBy == prior.startedBy,
                          successor.startedAt == prior.startedAt,
                          successor.revision == prior.revision + 1,
                          successor.mutationID != prior.mutationID,
                          successor.predecessorSessionSHA256 == prior.sessionSHA256 else {
                        throw SearchContractFailureV1.staleIndex
                    }
                }
            }
            return current
        }.sorted {
            $0.sessionID.uuidString.lowercased() < $1.sessionID.uuidString.lowercased()
        }

        var subjectsByID: [UUID: ProvisionalSubjectV1] = [:]
        for subject in provisionalSubjects {
            guard subjectsByID.updateValue(subject, forKey: subject.provisionalSubjectID) == nil else {
                throw SearchContractFailureV1.duplicateProjection
            }
        }
        let orderedPublications = publications.sorted {
            if $0.sessionID != $1.sessionID { return $0.sessionID.uuidString < $1.sessionID.uuidString }
            if $0.revision != $1.revision { return $0.revision < $1.revision }
            return $0.snapshotID.uuidString < $1.snapshotID.uuidString
        }
        var publicationsBySession: [UUID: [SurveyPublicationSnapshotV1]] = [:]
        for publication in orderedPublications {
            guard !publicationsBySession[publication.sessionID, default: []].contains(where: {
                $0.snapshotID == publication.snapshotID
            }) else {
                throw SearchContractFailureV1.duplicateProjection
            }
            publicationsBySession[publication.sessionID, default: []].append(publication)
        }

        var records: [SurveySessionSearchRecordV1] = []
        for session in orderedSessions {
            let provisional: ProvisionalSubjectV1?
            if case let .provisional(reference) = session.subject {
                provisional = subjectsByID[reference.provisionalSubjectID]
            } else {
                provisional = nil
            }
            let sessionPublications = publicationsBySession[session.sessionID] ?? []
            let currentPublication: SurveyPublicationSnapshotV1?
            if let reference = session.latestPublication {
                let matches = sessionPublications.filter {
                    $0.snapshotID == reference.snapshotID
                        && $0.revision == reference.revision
                        && $0.snapshotSHA256 == reference.snapshotSHA256
                }
                guard matches.count <= 1 else {
                    throw SearchContractFailureV1.duplicateProjection
                }
                currentPublication = matches.first
            } else {
                currentPublication = nil
            }
            records.append(try LocalSearchIndexStoreV1.surveySessionSearchRecord(
                from: session,
                publication: currentPublication,
                provisionalSubject: provisional,
                factState: factStates[session.sessionID],
                publicationState: publicationStates[session.sessionID]
            ))
        }
        records.sort { $0.projectionIdentity < $1.projectionIdentity }
        guard Set(records.map(\.projectionIdentity)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try SurveySessionSearchProjectionPolicyV1.validate($0) }
        return records
    }

    static let surveySessionReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_SURVEY_SESSION_TERMINAL_TIPS"
    static let surveySessionRestoreDisposition =
        "EXCLUDE_SESSION_ROWS_AND_REBUILD_AFTER_CANONICAL_RESTORE"
}

// MARK: - C27 asset-locator search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds the disposable locator rows from canonical locator heads and
    /// recorded resolution results.  It never accepts raw input bytes and it
    /// never promotes a search row into canonical locator state.
    static func assetLocatorSearchRecords(
        from locators: [AssetLocatorV1],
        resolutions: [LocatorResolutionV1] = []
    ) throws -> [AssetLocatorSearchRecordV1] {
        try AssetLocatorSearchPersistencePolicyV1().validate()
        guard locators.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              resolutions.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        try locators.forEach { try $0.validate() }
        try resolutions.forEach { try $0.validate() }

        let orderedLocators = locators.sorted {
            if $0.locatorID != $1.locatorID {
                return $0.locatorID.uuidString.lowercased()
                    < $1.locatorID.uuidString.lowercased()
            }
            return $0.revision < $1.revision
        }
        var latestByLocatorID: [UUID: AssetLocatorV1] = [:]
        for locator in orderedLocators {
            if let prior = latestByLocatorID[locator.locatorID],
               prior.revision == locator.revision {
                throw SearchContractFailureV1.duplicateProjection
            }
            latestByLocatorID[locator.locatorID] = locator
        }

        let currentLocators = latestByLocatorID.values.sorted {
            $0.locatorID.uuidString.lowercased() < $1.locatorID.uuidString.lowercased()
        }
        var records: [AssetLocatorSearchRecordV1] = []
        for locator in currentLocators {
            let matchingResolution = resolutions
                .filter {
                    $0.workspaceID == locator.workspaceID
                        && $0.matchedLocator?.locatorID == locator.locatorID
                        && $0.matchedLocator?.revision == locator.revision
                }
                .sorted {
                    if $0.evaluatedAt != $1.evaluatedAt {
                        return $0.evaluatedAt < $1.evaluatedAt
                    }
                    return $0.resolutionSHA256 < $1.resolutionSHA256
                }
                .last
            records.append(try LocalSearchIndexStoreV1.assetLocatorSearchRecord(
                from: locator,
                resolution: matchingResolution
            ))
        }

        // Keep bounded negative/ambiguous results searchable without copying
        // the input digest or candidate locator references into the index.
        for resolution in resolutions where resolution.matchedLocator == nil {
            let projection = try AssetLocatorReportProjectionV1(resolution: resolution)
            records.append(try LocalSearchIndexStoreV1.assetLocatorSearchRecord(
                from: projection
            ))
        }

        records.sort { $0.projectionIdentity < $1.projectionIdentity }
        guard records.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              Set(records.map(\.projectionIdentity)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try AssetLocatorSearchProjectionPolicyV1.validate($0) }
        return records
    }

    static let assetLocatorReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_ASSET_LOCATORS_AND_RESOLUTION_HISTORY"
    static let assetLocatorRestoreDisposition =
        "EXCLUDE_LOCATOR_ROWS_AND_REBUILD_AFTER_CANONICAL_RESTORE"
}

// MARK: - C28 schedule occurrence search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds the disposable schedule rows from frozen report projections.
    /// Inputs are already derived from canonical release/history records; this
    /// path never reinterprets a device time zone or treats notification
    /// delivery as an occurrence transition.
    static func scheduleOccurrenceSearchRecords(
        from projections: [ScheduleReportProjectionV1]
    ) throws -> [ScheduleOccurrenceSearchRecordV1] {
        try ScheduleOccurrenceSearchPersistencePolicyV1().validate()
        guard projections.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        try projections.forEach {
            try ScheduleReportProjectionPolicyV1.validate($0)
        }

        var records: [ScheduleOccurrenceSearchRecordV1] = []
        for projection in projections.sorted(by: { $0.projectionSHA256 < $1.projectionSHA256 }) {
            for occurrence in projection.occurrences {
                records.append(try LocalSearchIndexStoreV1.scheduleOccurrenceSearchRecord(
                    from: projection,
                    occurrence: occurrence
                ))
            }
        }
        guard records.count <= SearchContractLimitsV1.maximumProjectionRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        records.sort { $0.projectionIdentity < $1.projectionIdentity }
        guard Set(records.map(\.projectionIdentity)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try ScheduleOccurrenceSearchProjectionPolicyV1.validate($0) }
        return records
    }

    /// C22 rebuild admission requires an explicit current release frontier and
    /// an exact terminal occurrence event for every indexed row. Historical
    /// releases and nonterminal events remain openable through their canonical
    /// readers, but cannot be published as current search metadata.
    static func currentScheduleOccurrenceSearchRecords(
        from projections: [ScheduleReportProjectionV1],
        currentReleases: [ScheduleDefinitionReleaseReferenceV1],
        terminalOccurrenceEvents: [OccurrenceHistoryEventV1]
    ) throws -> [ScheduleOccurrenceSearchRecordV1] {
        try currentReleases.forEach { try $0.validate() }
        try terminalOccurrenceEvents.forEach { try $0.validateIntrinsic() }
        guard Set(currentReleases.map { "\($0.workspaceID.rawValue)|\($0.scheduleDefinitionID)" }).count == currentReleases.count,
              Set(terminalOccurrenceEvents.map(\.occurrenceID)).count == terminalOccurrenceEvents.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        let currentByDefinition = Dictionary(
            uniqueKeysWithValues: currentReleases.map {
                ("\($0.workspaceID.rawValue)|\($0.scheduleDefinitionID)", $0)
            }
        )
        let terminalByOccurrence = Dictionary(
            uniqueKeysWithValues: terminalOccurrenceEvents.map { ($0.occurrenceID, $0) }
        )
        let current = try projections.filter { projection in
            try ScheduleReportProjectionPolicyV1.validate(projection)
            let key = "\(projection.workspaceID)|\(projection.scheduleDefinitionID)"
            guard let release = currentByDefinition[key] else { return false }
            guard projection.scheduleRelease == release,
                  projection.reminderProjectionSHA256 == nil else {
                throw SearchContractFailureV1.scopeMismatch
            }
            for occurrence in projection.occurrences {
                guard let event = terminalByOccurrence[occurrence.occurrenceID],
                      event.workspaceID.rawValue == projection.workspaceID,
                      event.scheduleRelease == projection.scheduleRelease,
                      event.eventSHA256 == occurrence.historyEventSHA256 else {
                    throw SearchContractFailureV1.scopeMismatch
                }
            }
            return true
        }
        let indexedOccurrenceIDs = Set(current.flatMap { $0.occurrences.map(\.occurrenceID) })
        guard current.count == currentReleases.count,
              indexedOccurrenceIDs == Set(terminalOccurrenceEvents.map(\.occurrenceID)) else {
            throw SearchContractFailureV1.scopeMismatch
        }
        return try scheduleOccurrenceSearchRecords(from: current)
    }

    static let scheduleOccurrenceReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_SCHEDULE_RELEASE_AND_OCCURRENCE_HISTORY"
    static let scheduleOccurrenceRestoreDisposition =
        "EXCLUDE_SCHEDULE_ROWS_AND_REBUILD_AFTER_CANONICAL_RESTORE"
}

// MARK: - C29 plan placement search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds disposable plan placement rows from frozen report projections
    /// in deterministic order. Rebase previews, receipts, source bytes, and
    /// private locator bindings never become search rows.
    static func planPlacementSearchRecords(
        from projections: [PlanReportProjectionV1]
    ) throws -> [PlanPlacementSearchRecordV1] {
        try PlanPlacementSearchPersistencePolicyV1().validate()
        guard projections.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        try projections.forEach {
            try PlanReportProjectionPolicyV1.validate($0)
        }

        var records: [PlanPlacementSearchRecordV1] = []
        for projection in projections.sorted(by: { $0.projectionSHA256 < $1.projectionSHA256 }) {
            guard projection.placements.count <= PlanLimitsV1.maximumPlacements,
                  records.count <= SearchContractLimitsV1.maximumProjectionRecords
            else {
                throw SearchContractFailureV1.limitExceeded
            }
            for placement in projection.placements {
                records.append(try LocalSearchIndexStoreV1.planPlacementSearchRecord(
                    from: projection,
                    placement: placement
                ))
            }
        }
        guard records.count <= SearchContractLimitsV1.maximumProjectionRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        records.sort { $0.projectionIdentity < $1.projectionIdentity }
        guard Set(records.map(\.projectionIdentity)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try PlanPlacementSearchProjectionPolicyV1.validate($0) }
        return records
    }

    static let planPlacementReplayDisposition =
        "DROP_AND_REBUILD_FROM_FROZEN_PLAN_REPORT_PROJECTIONS"
    static let planPlacementRestoreDisposition =
        "EXCLUDE_PLAN_ROWS_AND_REBUILD_AFTER_CANONICAL_RESTORE"
    static let planPlacementEraseDisposition =
        "DROP_AND_REBUILD_AFTER_PLAN_ERASE"
}

// MARK: - C19 current plan-document search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Computes current document, content-revision, and placement tips from
    /// complete canonical histories. No caller-provided historic selection is
    /// accepted, and documents with zero current placements still emit a row.
    static func planDocumentSearchRecords(
        documentHistory: [PlanDocumentV1],
        revisionHistory: [PlanRevisionV1],
        placementHistory: [PlanPlacementV1],
        offlineReadiness: [OfflineWorkPacketReadinessV1] = [],
        workSurfaces: [PlanWorkSurfaceStateV1] = []
    ) throws -> [PlanDocumentSearchRecordV1] {
        try PlanDocumentSearchPersistencePolicyV1().validate()
        guard documentHistory.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              revisionHistory.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              placementHistory.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              offlineReadiness.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              workSurfaces.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        try PlanLifecycleClosureV1(
            documentHistory: documentHistory,
            revisionHistory: revisionHistory,
            placementHistory: placementHistory,
            receipts: []
        ).validate()
        let workspaceIDs = Set(documentHistory.map(\.workspaceID)
            + revisionHistory.map(\.workspaceID)
            + placementHistory.map(\.workspaceID))
        let documentReferences = try documentHistory.map { try $0.reference }
        guard workspaceIDs.count <= 1,
              revisionHistory.allSatisfy({ documentReferences.contains($0.planDocument) }) else {
            throw SearchContractFailureV1.scopeMismatch
        }

        let currentDocuments = Dictionary(grouping: documentHistory, by: \.planDocumentID)
            .values.compactMap { $0.max(by: { $0.revision < $1.revision }) }
            .sorted { $0.planDocumentID.uuidString < $1.planDocumentID.uuidString }
        let revisionsByDocument = Dictionary(
            grouping: revisionHistory,
            by: { $0.planDocument.planDocumentID }
        )
        let currentPlacements = Dictionary(grouping: placementHistory, by: \.placementID)
            .values.compactMap { $0.max(by: { $0.revision < $1.revision }) }
        try offlineReadiness.forEach { try $0.validateIntrinsic() }
        try workSurfaces.forEach { try $0.validateIntrinsic() }
        let allRevisionReferences = try revisionHistory.map { try $0.reference }
        let revisionByReference = Dictionary(uniqueKeysWithValues:
            try revisionHistory.map { (try $0.reference, $0) })
        func packetItemKey(
            workspaceID: WorkspaceID,
            packet: WorkPacketManifestReferenceV1,
            item: WorkPacketItemReferenceV1
        ) -> String {
            "\(workspaceID.rawValue.uuidString)|\(packet.packetID.uuidString)|" +
                "\(packet.packetVersion)|\(item.itemID)|\(item.itemSHA256)"
        }
        let absentPlanItemKeys = Set(offlineReadiness.compactMap { readiness in
            guard readiness.planRevision == nil || readiness.applicability == .notApplicable else {
                return nil
            }
            return packetItemKey(
                workspaceID: readiness.workspaceID,
                packet: readiness.packet,
                item: readiness.item
            )
        })
        let currentRevisionReferences = try revisionsByDocument.values.compactMap {
            try $0.max(by: { $0.revision < $1.revision }).map { try $0.reference }
        }
        guard offlineReadiness.allSatisfy({ readiness in
                  guard let planRevision = readiness.planRevision else {
                      return readiness.applicability != .required
                  }
                  guard let disposition = readiness.revisionDisposition else { return false }
                  return workspaceIDs.contains(readiness.workspaceID)
                      && allRevisionReferences.contains(planRevision)
                      && readiness.contentBinding == revisionByReference[planRevision]?.contentBinding
                      && (disposition == .historic
                          || currentRevisionReferences.contains(planRevision))
              }),
              workSurfaces.allSatisfy({
                  workspaceIDs.contains($0.workspaceID)
                      && allRevisionReferences.contains($0.planRevision)
              }) else {
            throw SearchContractFailureV1.scopeMismatch
        }

        var records: [PlanDocumentSearchRecordV1] = []
        for document in currentDocuments {
            guard let revision = revisionsByDocument[document.planDocumentID]?
                .max(by: { $0.revision < $1.revision }) else {
                throw SearchContractFailureV1.staleIndex
            }
            let reference = try revision.reference
            let placementCount = currentPlacements.filter { $0.planRevision == reference }.count
            let readinessMetadata = try offlineReadiness.filter {
                $0.revisionDisposition == .current
                    && $0.planRevision == reference
            }.map(PlanOfflineReadinessSearchMetadataV1.init)
            let workSurfaceMetadata = try workSurfaces.filter {
                $0.planRevision == reference
                    && $0.applicability != .notApplicable
                    && !absentPlanItemKeys.contains(packetItemKey(
                        workspaceID: $0.workspaceID,
                        packet: $0.packet,
                        item: $0.item
                    ))
            }.map(PlanWorkSurfaceSearchMetadataV1.init)
            records.append(try LocalSearchIndexStoreV1.planDocumentSearchRecord(
                currentDocument: document,
                currentRevision: revision,
                currentPlacementCount: placementCount,
                offlineReadiness: readinessMetadata,
                workSurfaces: workSurfaceMetadata
            ))
        }
        records.sort { $0.projectionIdentity < $1.projectionIdentity }
        guard records.count <= SearchContractLimitsV1.maximumProjectionRecords,
              Set(records.map(\.projectionIdentity)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try PlanDocumentSearchProjectionPolicyV1.validate($0) }
        return records
    }

    static let planDocumentReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_PLAN_HISTORY"
    static let planDocumentRestoreDisposition =
        "EXCLUDE_DERIVED_PLAN_DOCUMENT_ROWS_AND_REBUILD_AFTER_CANONICAL_RESTORE"
    static let planDocumentEraseDisposition =
        "DROP_AND_REBUILD_AFTER_PLAN_DELETE_OR_ERASE"
}

// MARK: - C37 current placement-pose search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds current pose-tip rows from immutable report projections in a
    /// stable order. Replays, restores, and Erase drop these rows and invoke
    /// this route again; no sensor or private locator input is accepted.
    static func placementPoseSearchRecords(
        from projections: [C37PlacementPoseReportProjectionV1]
    ) throws -> [C37PoseSearchRecordV1] {
        try C37PoseSearchPersistencePolicyV1().validate()
        guard projections.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        try projections.forEach { try C37PoseReportProjectionPolicyV1.validate($0) }

        var records: [C37PoseSearchRecordV1] = []
        for projection in projections.sorted(by: { $0.projectionSHA256 < $1.projectionSHA256 }) {
            let rowsByTip = projection.currentTipReferences.compactMap { reference in
                projection.history.first {
                    $0.eventID == reference.eventID
                        && $0.axisID == reference.axisID.rawValue
                        && $0.revision == reference.revision
                        && $0.eventSHA256 == reference.eventSHA256
                }
            }
            guard rowsByTip.count == projection.currentTipReferences.count else {
                throw SearchContractFailureV1.staleIndex
            }
            for row in rowsByTip {
                records.append(try LocalSearchIndexStoreV1.placementPoseSearchRecord(
                    from: projection, row: row
                ))
            }
        }
        guard records.count <= SearchContractLimitsV1.maximumProjectionRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        records.sort { $0.projectionIdentity < $1.projectionIdentity }
        guard Set(records.map(\.projectionIdentity)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try C37PoseSearchProjectionPolicyV1.validate($0) }
        return records
    }

    static let placementPoseReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_POSE_HISTORY"
    static let placementPoseRestoreDisposition =
        "EXCLUDE_POSE_ROWS_AND_REBUILD_AFTER_CANONICAL_RESTORE"
    static let placementPoseEraseDisposition =
        "DROP_AND_REBUILD_AFTER_POSE_ERASE"
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Search_SearchIndexRebuildCoordinatorV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift", role: .search)
}

enum C31LightingConsumerBoundary_Infrastructure_Search_SearchIndexRebuildCoordinatorV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/search-index-rebuild-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Search_SearchIndexRebuildCoordinatorV1 {
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

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Search_SearchIndexRebuildCoordinatorV1_swift {
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

enum C45AcceptedLabelIndexRebuildBoundaryV1 {
    static let rebuildsTypedMetadata=true
    static func metadata(from rows:[AcceptedLabelGenerationSnapshotRow])throws->[AcceptedLabelSearchMetadataV1]{try rows.map{try .init($0.value())}.sorted{$0.snapshotID.uuidString<$1.snapshotID.uuidString}}
}

// MARK: - C48 portable-review rebuild boundary

enum C48PortableReviewSearchRebuildBoundaryV1 {
    static let rebuildsOnlyDerivedMetadata = true
    static let responseHistoryIsReadOnly = true
    static let capabilityBytesRebuilt = false
    static let capabilityProofBytesRebuilt = false
    static let responseBodyRebuilt = false
    static let rawRequestResponseBytesRebuilt = false
    static let workspaceAndReplicaIdentityRebuilt = false
    static let staleIndexMustBeDiscarded = true

    static func validate(_ projection: C48PortableReviewDerivedHistoryProjectionV1) throws {
        try projection.validate()
    }

    static func metadata(
        state: ReviewRequestStateProjectionV1,
        response: ExternalReviewResponseRecordV1? = nil,
        conflictCount: Int = 0
    ) throws -> C48PortableReviewDerivedHistoryProjectionV1 {
        let projection = try C48PortableReviewSearchBoundaryV1.derivedHistory(
            state: state, response: response, conflictCount: conflictCount
        )
        try validate(projection)
        return projection
    }
}

// MARK: - C49 work-resource search rebuild boundary

/// C49 search is a disposable projection of canonical work-resource history.
/// Rebuilds never materialize private cost, note, locator, or inventory data.
enum C49WorkResourceSearchRebuildBoundaryV1 {
    static let canonicalRecordType = "WorkResourceEntryV1"
    static let rebuildsOnlyCurrentDerivedMetadata = true
    static let directCostRowsRebuilt = false
    static let internalNotesRebuilt = false
    static let privateLocatorsRebuilt = false
    static let liveInventoryLookup = false
    static let rebuildSourceIsCanonicalReceiptHistory = true

    static func validateField(_ fieldID: String) throws {
        try C49WorkResourceLocalSearchBoundaryV1.validateField(fieldID)
    }
}

enum C55PartsStockSearchRebuildBoundaryV1 {
    static let source = "LocalPartDefinitionV1"
    static let rebuildsOnlyDerivedCatalogTokens = true
    static let balancesOrStorageAreIndexed = false
    static func validateField(_ fieldID: String) throws { try C55PartsStockLocalSearchBoundaryV1.validateField(fieldID) }
}


enum C50IncumbentFileExchangeSearchRebuildBoundaryV1 {
    static let rebuildsAdapterSessionOrProfileState = false
    static let rebuildsSourceQuarantineOrExternalPath = false
    static let delegatesAcceptedRowsToExistingTargetProjectionOwners = true
    static let staleDerivedIndexMayBeDiscarded = true
    static let canonicalWriterInvokedDuringRebuild = false

    static func validate() -> Bool {
        !rebuildsAdapterSessionOrProfileState
            && !rebuildsSourceQuarantineOrExternalPath
            && delegatesAcceptedRowsToExistingTargetProjectionOwners
            && staleDerivedIndexMayBeDiscarded
            && !canonicalWriterInvokedDuringRebuild
            && C50IncumbentFileExchangeLocalSearchBoundaryV1.validate()
    }
}

// MARK: - C34 route snapshot search exclusion

enum C34RouteSnapshotSearchRebuildBoundaryV1 {
    static let snapshotType: Any.Type = SceneNavigationSnapshotV1.self
    static let routeSnapshotIndexed = false
    static let stableRouteIdentifiersIndexed = false
    static let fallbackReasonsIndexed = false
    static let searchQueryRecoveredFromRouteState = false
    static let rebuildInvokesRouteResolution = false

    static func validate(_ lifecycle: SceneNavigationLifecycleDispositionV1 = .init()) -> Bool {
        !lifecycle.searchIncluded && !routeSnapshotIndexed
            && !searchQueryRecoveredFromRouteState
            && !rebuildInvokesRouteResolution
    }
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Search_SearchIndexRebuildCoordinatorV1_swift {
    static let acceptedCanonicalRecordPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let acceptedEventPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let duplicateProjectionPersistence: ServiceRequestPersistenceClassV1 = .nonpersistentDerived
    static let rawCapabilityPersistence: ServiceRequestPersistenceClassV1 = .prohibitedPersistent
    static let acceptedLifecycleEnrollment: ServiceRequestPersistenceEnrollmentV1.Type = ServiceRequestPersistenceEnrollmentV1.self
    static let cloneOrForkInvalidatesActiveCapabilities: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities
    static let duplicateProjectionIsRebuildable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable &&
        !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityIsExcludedFromReportsAndDiagnostics: Bool =
        !ServiceRequestLifecycleRegistrationBoundaryV1.rawCapabilityAppearsInReportsOrDiagnostics
    static let sharedPortableFilesAreRecallable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled
    static let unverifiedAssertionsAreVerified: Bool = false
    static let automaticWorkNetworkSLAOrAIClaimsPermitted: Bool = false
}

// MARK: - C53 service-reliability deterministic rebuild

enum C53ServiceReliabilitySearchRebuildBoundaryV1 {
    static let rebuildsFromCanonicalReportProjection = true
    static let rebuildIsDeterministic = true
    static let indexIsDroppedBeforeRestoreReplayPublication = true
    static let exactMetricValuesRemainNonSearchable = true

    static func records(
        from projections: [C53ServiceReliabilityReportProjectionV1]
    ) throws -> [C53ServiceReliabilitySearchProjectionV1] {
        let values = try projections.map {
            try C53ServiceReliabilitySearchProjectionBoundaryV1.projection($0)
        }
        let sorted = values.sorted {
            ($0.workspaceID.rawValue.uuidString, $0.subjectID.uuidString, $0.reliabilityIdentityEpochID.uuidString)
                < ($1.workspaceID.rawValue.uuidString, $1.subjectID.uuidString, $1.reliabilityIdentityEpochID.uuidString)
        }
        guard zip(sorted, sorted.dropFirst()).allSatisfy({ lhs, rhs in
            (lhs.workspaceID.rawValue, lhs.subjectID, lhs.reliabilityIdentityEpochID)
                != (rhs.workspaceID.rawValue, rhs.subjectID, rhs.reliabilityIdentityEpochID)
        }) else {
            throw SearchContractFailureV1.duplicateProjection
        }
        return sorted
    }
}

// MARK: - C57 deterministic My Day index rebuild

enum C57MyDaySearchRebuildBoundaryV1 {
    static let rebuildsFromCanonicalPlansAndCurrentSourceFrontiers = true
    static let rebuildWritesNoMyDayCanonicalState = true
    static let staleIndexIsDroppedBeforePublication = true

    static func records(
        plans: [MyDayPlanV1],
        readiness: [MyDayReadinessProjectionV1]
    ) throws -> [C57MyDaySearchRecordV1] {
        guard plans.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              readiness.count == plans.count else {
            throw SearchContractFailureV1.limitExceeded
        }
        try plans.forEach { try $0.validate() }
        try readiness.forEach { try $0.validate() }
        let grouped = Dictionary(grouping: readiness, by: \.plan)
        guard Set(plans.map(\.key)).count == plans.count,
              grouped.values.allSatisfy({ $0.count == 1 }) else {
            throw SearchContractFailureV1.duplicateProjection
        }
        let planReferences = try plans.map(MyDayPlanReferenceV1.init)
        guard Set(planReferences).count == planReferences.count,
              Set(grouped.keys) == Set(planReferences) else {
            throw SearchContractFailureV1.staleIndex
        }
        let values = try plans.flatMap { plan -> [C57MyDaySearchRecordV1] in
            let reference = try MyDayPlanReferenceV1(plan)
            guard let source = grouped[reference]?.first else {
                throw SearchContractFailureV1.staleIndex
            }
            return try C57MyDayLocalSearchIndexBoundaryV1.records(
                plan: plan, readiness: source
            )
        }.sorted { $0.projectionIdentity < $1.projectionIdentity }
        guard values.count <= SearchContractLimitsV1.maximumProjectionRecords,
              Set(values.map(\.projectionIdentity)).count == values.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        return values
    }
}

// MARK: - C05 round-session deterministic search rebuild

enum C05RoundSessionSearchRebuildBoundaryV1 {
    static let rebuildsFromExactCurrentCanonicalFrontiers = true
    static let rebuildWritesNoRoundSessionCanonicalState = true
    static let staleProjectionIsDroppedBeforePublication = true
    static let routeDueReminderNetworkOrTeamStateIndexed = false

    static func records(
        progress: [C05RoundSessionProgressReportProjectionV1],
        closeouts: [C05RoundSessionCloseoutReportProjectionV1]
    ) throws -> [C05RoundSessionSearchProjectionV1] {
        guard progress.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              closeouts.count <= progress.count else {
            throw SearchContractFailureV1.limitExceeded
        }
        try progress.forEach { try $0.validate() }
        try closeouts.forEach { try $0.validate() }

        let progressBySession = Dictionary(grouping: progress, by: \.session)
        let closeoutBySession = Dictionary(grouping: closeouts, by: \.progress.session)
        guard progressBySession.values.allSatisfy({ $0.count == 1 }),
              closeoutBySession.values.allSatisfy({ $0.count == 1 }),
              Set(closeoutBySession.keys).isSubset(of: Set(progressBySession.keys)) else {
            throw SearchContractFailureV1.duplicateProjection
        }

        let values = try progress.map { value in
            try C05RoundSessionSearchProjectionBoundaryV1.projection(
                progress: value,
                closeout: closeoutBySession[value.session]?.first
            )
        }.sorted {
            ($0.workspaceID.rawValue.uuidString, $0.session.sessionID.uuidString)
                < ($1.workspaceID.rawValue.uuidString, $1.session.sessionID.uuidString)
        }
        let stableIDs = values.map {
            $0.workspaceID.rawValue.uuidString.lowercased()
                + "|"
                + $0.session.sessionID.uuidString.lowercased()
        }
        guard values.count <= SearchContractLimitsV1.maximumProjectionRecords,
              Set(stableIDs).count == values.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        return values
    }

    /// Receipt provenance is journal-backed canonical evidence. Rebuild uses
    /// it only to prove the existing round projection frontier; preview input
    /// bytes, scan payloads, and locator candidate detail never enter search.
    static func records(
        progress: [C05RoundSessionProgressReportProjectionV1],
        closeouts: [C05RoundSessionCloseoutReportProjectionV1],
        scanEntryReceipts: [InstallationScanEntryReceiptV1],
        flows: [ScanToWorkFlowV1]
    ) throws -> [C05RoundSessionSearchProjectionV1] {
        guard scanEntryReceipts.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              flows.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              Set(scanEntryReceipts.map(\.receiptSHA256)).count == scanEntryReceipts.count,
              Set(flows.map { $0.preview.previewSHA256 }).count == flows.count,
              Set(scanEntryReceipts.map(\.previewSHA256))
                == Set(flows.map { $0.preview.previewSHA256 }) else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try flows.forEach { try $0.validateIntrinsic() }
        let flowsByPreview = Dictionary(uniqueKeysWithValues: flows.map {
            ($0.preview.previewSHA256, $0)
        })
        try scanEntryReceipts.forEach { receipt in
            guard let flow = flowsByPreview[receipt.previewSHA256] else {
                throw SearchContractFailureV1.staleIndex
            }
            let request = try ScanToWorkStartRequestV1(
                flow: flow,
                policy: receipt.policy,
                roundMutation: receipt.roundMutationReceipt.mutation,
                explicitUserConfirmation: true
            )
            try receipt.validate(request: request)
        }
        let progressReferences = Set(progress.map(\.session))
        guard scanEntryReceipts.allSatisfy({
            progressReferences.contains($0.roundMutationReceipt.sessionFrontier)
        }) else {
            throw SearchContractFailureV1.staleIndex
        }
        return try records(progress: progress, closeouts: closeouts)
    }
}


// MARK: - C14 private system-discovery rebuild enrollment

enum PrivateSystemDiscoverySearchRebuildBoundaryV1 {
    static let namedIndex = PrivateSystemDiscoveryLifecycleV1.namedIndex
    static let usesDefaultIndex = false
    static let sourceIsSelectedRealWorkspaceOnly = true
    static let projectionIsDerivedOnly = true

    static func rebuild(
        operationID: PrivateSystemDiscoveryOperationIDV1,
        index: any PrivateSystemDiscoveryIndexLifecyclePortV1,
        workspaceID: WorkspaceID,
        workspaceRevision: UInt64,
        deletionFrontier: UInt64,
        descriptors: [PrivateSystemDiscoveryProjectionDescriptorV1],
        manifest: PrivateSystemDiscoveryManifestV1,
        optIn: PrivateSystemDiscoveryOptInV1,
        availability: [AppIntentAvailabilityV1],
        now: Date
    ) async throws {
        try operationID.validate()
        guard namedIndex == "PRIVATE_SYSTEM_DISCOVERY_INDEX_V1",
              !usesDefaultIndex,
              sourceIsSelectedRealWorkspaceOnly,
              projectionIsDerivedOnly,
              operationID.operation == .rebuild,
              operationID.workspaceID == workspaceID else {
            throw PrivateSystemDiscoveryFailureV1.invalidValue
        }
        try await index.rebuild(
            operationID: operationID,
            workspaceID: workspaceID,
            workspaceRevision: workspaceRevision,
            deletionFrontier: deletionFrontier,
            descriptors: descriptors,
            manifest: manifest,
            optIn: optIn,
            availability: availability,
            now: now
        )
    }
}

// MARK: - C17 exterior-lighting day inventory search rebuild

enum C17LightingDaySearchRebuildBoundaryV1 {
    static let projectionIsDerivedAndDisposable = true
    static let canonicalWriterIsUntouched = true
    static let safetyStoppedWorkflowsAreNotDiscoverable = true
    static let privateSafetyRouteActorNotesAndMediaAreExcluded = true

    static func records(
        workflows: [LightingDayInventoryWorkflowV1]
    ) throws -> [C17LightingDaySearchRecordV1] {
        guard workflows.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        try workflows.forEach { try $0.validateIntrinsic() }
        let eligible = workflows.filter { $0.state != .safetyStopped }
        let grouped = Dictionary(grouping: eligible, by: \.workflowID)
        let current = try grouped.values.map { history -> LightingDayInventoryWorkflowV1 in
            let ordered = history.sorted { $0.revision < $1.revision }
            guard ordered.first?.revision == 1,
                  Set(ordered.map(\.revision)).count == ordered.count else {
                throw SearchContractFailureV1.duplicateProjection
            }
            for index in ordered.indices.dropFirst() {
                try ordered[index].validateSuccessor(of: ordered[ordered.index(before: index)])
            }
            return ordered[ordered.index(before: ordered.endIndex)]
        }
        let values = try current.map {
            try C17LightingDaySearchRecordV1(workflow: $0)
        }.sorted()
        guard Set(values.map(\.projectionIdentity)).count == values.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        return values
    }
}

enum C18LightingNightSearchRebuildBoundaryV1{
    static let projectionIsDerivedAndDisposable=true
    static func records(workflows:[LightingNightWorkflowV1])throws->[C18LightingNightSearchRecordV1]{
        guard workflows.count<=SearchContractLimitsV1.maximumCanonicalRecords else{throw SearchContractFailureV1.limitExceeded}
        try workflows.forEach{$0.validateIntrinsic()}
        let current=try Dictionary(grouping:workflows,by:\.workflowID).values.map{history->LightingNightWorkflowV1 in
            let ordered=history.sorted{$0.revision<$1.revision}
            guard ordered.first?.revision==1,Set(ordered.map(\.revision)).count==ordered.count else{throw SearchContractFailureV1.duplicateProjection}
            for i in ordered.indices.dropFirst(){try ordered[i].validateSuccessor(of:ordered[ordered.index(before:i)])}
            return ordered[ordered.index(before:ordered.endIndex)]
        }
        let values=try current.map{try C18LightingNightSearchRecordV1(workflow:$0)}.sorted()
        guard Set(values.map(\.projectionIdentity)).count==values.count else{throw SearchContractFailureV1.duplicateProjection}
        return values
    }
}

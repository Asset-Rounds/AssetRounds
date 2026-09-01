import Foundation

@MainActor
protocol ServiceRequestManualDuplicateProjectingV1: AnyObject {
    func projectCandidates(
        workspaceID: WorkspaceID,
        record: ServiceRequestRecordV1
    ) throws -> ServiceRequestDuplicateProjectionV1
}

struct ServiceRequestWorkflowContextV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let expectedRevision: WorkspaceExpectedRevisionV1
    let records: [ServiceRequestRecordV1]
    let dispositionEvents: [ServiceRequestDispositionEventV1]
    let workLinkEvents: [ServiceRequestWorkLinkEventV1]
    let draft: ServiceRequestDraftReferenceV1?

    init(
        workspaceID: WorkspaceID,
        expectedRevision: WorkspaceExpectedRevisionV1,
        records: [ServiceRequestRecordV1],
        dispositionEvents: [ServiceRequestDispositionEventV1],
        workLinkEvents: [ServiceRequestWorkLinkEventV1],
        draft: ServiceRequestDraftReferenceV1? = nil
    ) throws {
        guard expectedRevision.workspaceID == workspaceID else {
            throw ServiceRequestWorkflowFailureV1.invalidContext
        }
        try records.forEach { try $0.validate() }
        try dispositionEvents.forEach { try $0.validate() }
        try workLinkEvents.forEach { try $0.validate() }
        guard records.allSatisfy({ $0.workspaceID == workspaceID }),
              dispositionEvents.allSatisfy({ $0.workspaceID == workspaceID }),
              workLinkEvents.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw ServiceRequestWorkflowFailureV1.invalidContext
        }
        self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision
        self.records = records
        self.dispositionEvents = dispositionEvents
        self.workLinkEvents = workLinkEvents
        self.draft = draft
    }
}

struct ServiceRequestWorkflowProjectionV1: Equatable, Sendable {
    let needsTriage: ServiceRequestNeedsTriageProjectionV1
    let availableDispositions: [ServiceRequestImportDispositionV1]
    let draftCompatibility: ServiceRequestDraftCompatibilityV1?
    let claims: ServiceRequestWorkflowClaimsV1
    let canCommitDraft: Bool
}

struct ServiceRequestPortablePreviewCommandV1: Equatable, Sendable {
    let expectedRevision: WorkspaceExpectedRevisionV1
    let release: PortableServiceRequestProtocolReleaseV1
    let invitation: PortableServiceRequestInvitationV1
    let submission: PortableServiceRequestSubmissionV1
    let canonicalSourceBytes: CanonicalServiceRequestSourceBytesV1
    let disposition: ServiceRequestImportDispositionV1
    let selectedDuplicate: ServiceRequestRevisionReferenceV1?
    let reason: String?
    let mutationID: MutationIDV1
}

struct ServiceRequestDispositionPreviewCommandV1: Equatable, Sendable {
    let record: ServiceRequestRecordV1
    let expectedRevision: WorkspaceExpectedRevisionV1
    let disposition: ServiceRequestImportDispositionV1
    let selectedDuplicate: ServiceRequestRevisionReferenceV1?
    let reason: String?
    let predecessor: ServiceRequestDispositionEventV1?
    let duplicateProjection: ServiceRequestDuplicateProjectionV1
    let mutationID: MutationIDV1
}

struct ServiceRequestWorkPreviewCommandV1: Equatable, Sendable {
    let request: ServiceRequestRevisionReferenceV1
    let expectedRevision: WorkspaceExpectedRevisionV1
    let work: ServiceRequestCanonicalWorkPreviewV1
    let mutationID: MutationIDV1
}

enum ServiceRequestWorkflowCommandV1: Equatable, Sendable {
    case previewManual(
        expectedRevision: WorkspaceExpectedRevisionV1,
        intake: ServiceRequestManualIntakeV1,
        decision: ServiceRequestManualDecisionV1,
        mutationID: MutationIDV1
    )
    case commitManual(ServiceRequestManualPreviewV1)
    case recoverManual(ServiceRequestManualPreviewV1)
    case previewPortable(ServiceRequestPortablePreviewCommandV1)
    case commitPortable(ServiceRequestImportPreviewV1)
    case recoverPortable(ServiceRequestImportPreviewV1)
    case previewDisposition(ServiceRequestDispositionPreviewCommandV1)
    case commitDisposition(ServiceRequestDispositionPlanV1)
    case recoverDisposition(ServiceRequestDispositionPlanV1)
    case previewWorkConversion(ServiceRequestWorkPreviewCommandV1)
    case previewWorkReversal(
        predecessor: ServiceRequestWorkLinkEventV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    )
    case commitWork(ServiceRequestWorkConversionPlanV1)
    case recoverWork(ServiceRequestWorkConversionPlanV1)
    case makeStatusArtifact(
        projection: ServiceRequestStateProjectionV1,
        customerNote: String?
    )
}

enum ServiceRequestWorkflowOutcomeV1: Equatable, Sendable {
    case manualPreview(ServiceRequestManualPreviewV1)
    case manualReceipt(ServiceRequestManualReceiptV1)
    case portablePreview(ServiceRequestImportPreviewV1)
    case portableReceipt(ServiceRequestImportReceiptV1)
    case dispositionPreview(ServiceRequestDispositionPlanV1)
    case dispositionReceipt(ServiceRequestDispositionReceiptV1)
    case workPreview(ServiceRequestWorkConversionPlanV1)
    case workReceipt(ServiceRequestWorkConversionReceiptV1)
    case statusArtifact(ServiceRequestStatusArtifactV1)
}

@MainActor
final class ServiceRequestWorkflowCoordinatorV1 {
    private let canonical: ServiceRequestCoordinatorV1
    private let manualDuplicates: any ServiceRequestManualDuplicateProjectingV1
    private let clock: any ApplicationClock

    init(
        canonical: ServiceRequestCoordinatorV1,
        manualDuplicates: any ServiceRequestManualDuplicateProjectingV1,
        clock: any ApplicationClock
    ) {
        self.canonical = canonical
        self.manualDuplicates = manualDuplicates
        self.clock = clock
    }

    func project(_ context: ServiceRequestWorkflowContextV1) throws
        -> ServiceRequestWorkflowProjectionV1 {
        let latestRecords = Dictionary(
            grouping: context.records,
            by: \.recordID
        ).compactMap { _, values in values.max(by: { $0.revision < $1.revision }) }
        let disposedIDs = Set(context.dispositionEvents.map(\.request.recordID))
        let items = try latestRecords
            .filter { !disposedIDs.contains($0.recordID) }
            .map { record in
                try ServiceRequestNeedsTriageItemV1(
                    request: record.reference,
                    source: record.source,
                    siteID: record.scope.siteID,
                    assetIDs: record.scope.assets.map(\.assetID).sorted {
                        $0.uuidString < $1.uuidString
                    },
                    searchableText: record.body.requestText,
                    recordedAt: record.recordedAt
                )
            }
            .sorted { $0.request.recordID.uuidString < $1.request.recordID.uuidString }
        return .init(
            needsTriage: .init(
                workspaceID: context.workspaceID,
                items: items,
                derived: true,
                rebuildable: true
            ),
            availableDispositions: ServiceRequestImportDispositionV1.allCases,
            draftCompatibility: context.draft?.compatibility,
            claims: .init(),
            canCommitDraft: context.draft?.compatibility == .current
        )
    }

    func execute(_ command: ServiceRequestWorkflowCommandV1) async throws
        -> ServiceRequestWorkflowOutcomeV1 {
        switch command {
        case let .previewManual(expectedRevision, intake, decision, mutationID):
            return .manualPreview(try canonical.previewManualIntake(
                expectedRevision: expectedRevision,
                intake: intake,
                decision: decision,
                mutationID: mutationID,
                projectDuplicates: { [manualDuplicates] record in
                    try manualDuplicates.projectCandidates(
                        workspaceID: expectedRevision.workspaceID,
                        record: record
                    )
                }
            ))
        case let .commitManual(preview):
            return .manualReceipt(try canonical.commitManualIntake(preview))
        case let .recoverManual(preview):
            return .manualReceipt(try canonical.recoverManualIntake(preview))
        case let .previewPortable(value):
            return .portablePreview(try await canonical.previewPortableImport(
                expectedRevision: value.expectedRevision,
                release: value.release,
                invitation: value.invitation,
                submission: value.submission,
                canonicalSourceBytes: value.canonicalSourceBytes,
                disposition: value.disposition,
                selectedDuplicate: value.selectedDuplicate,
                reason: value.reason,
                mutationID: value.mutationID
            ))
        case let .commitPortable(preview):
            return .portableReceipt(try await canonical.commitImport(preview))
        case let .recoverPortable(preview):
            return .portableReceipt(try await canonical.recoverImport(preview))
        case let .previewDisposition(value):
            return .dispositionPreview(try canonical.previewDisposition(
                record: value.record,
                expectedRevision: value.expectedRevision,
                disposition: value.disposition,
                selectedDuplicate: value.selectedDuplicate,
                reason: value.reason,
                predecessor: value.predecessor,
                duplicateProjection: value.duplicateProjection,
                mutationID: value.mutationID
            ))
        case let .commitDisposition(plan):
            return .dispositionReceipt(try canonical.commitDisposition(plan))
        case let .recoverDisposition(plan):
            return .dispositionReceipt(try canonical.recoverDisposition(plan))
        case let .previewWorkConversion(value):
            return .workPreview(try canonical.previewWorkConversion(
                request: value.request,
                expectedRevision: value.expectedRevision,
                work: value.work,
                predecessor: nil,
                mutationID: value.mutationID
            ))
        case let .previewWorkReversal(predecessor, expectedRevision, mutationID):
            return .workPreview(try canonical.previewWorkLinkReversal(
                predecessor: predecessor,
                expectedRevision: expectedRevision,
                mutationID: mutationID
            ))
        case let .commitWork(plan):
            return .workReceipt(try canonical.commitWorkConversion(plan))
        case let .recoverWork(plan):
            return .workReceipt(try canonical.recoverWorkConversion(plan))
        case let .makeStatusArtifact(projection, customerNote):
            return .statusArtifact(try ServiceRequestStatusArtifactV1(
                projection: projection,
                customerNote: customerNote,
                generatedAt: clock.now()
            ))
        }
    }
}

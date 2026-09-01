import Foundation

enum ServiceRequestWorkflowFailureV1: Error, Equatable, Sendable {
    case invalidContext
    case invalidManualSource
    case invalidDecision
    case duplicateOutsideScope
    case stalePreview
    case receiptMismatch
    case draftUnavailable
    case incompatibleDraft
    case unsupportedMigration
}

enum ServiceRequestDraftCompatibilityV1: String, Codable, Equatable, Sendable {
    case current = "CURRENT"
    case migrationRequired = "MIGRATION_REQUIRED"
    case unsupported = "UNSUPPORTED"
}

/// A proof-free bridge to the draft owner. The workflow never persists draft
/// bytes and cannot claim that an incompatible draft was migrated.
struct ServiceRequestDraftReferenceV1: Codable, Equatable, Hashable, Sendable {
    let draftID: UUID
    let draftRevision: UInt64
    let draftSHA256: String
    let compatibility: ServiceRequestDraftCompatibilityV1

    init(
        draftID: UUID,
        draftRevision: UInt64,
        draftSHA256: String,
        compatibility: ServiceRequestDraftCompatibilityV1
    ) throws {
        try ServiceRequestLimitsV1.id(draftID)
        try ServiceRequestLimitsV1.digest(draftSHA256)
        guard draftRevision > 0 else { throw ServiceRequestWorkflowFailureV1.invalidContext }
        self.draftID = draftID
        self.draftRevision = draftRevision
        self.draftSHA256 = draftSHA256
        self.compatibility = compatibility
    }
}

struct ServiceRequestManualIntakeV1: Equatable, Hashable, Sendable {
    let source: ServiceRequestSourceKindV1
    let scope: ServiceRequestScopeSnapshotV1
    let body: ServiceRequestSubmissionBodyV1
    let mediaManifest: ServiceRequestMediaManifestV1

    init(
        source: ServiceRequestSourceKindV1,
        scope: ServiceRequestScopeSnapshotV1,
        body: ServiceRequestSubmissionBodyV1,
        mediaManifest: ServiceRequestMediaManifestV1
    ) throws {
        guard source != .portableSubmission else {
            throw ServiceRequestWorkflowFailureV1.invalidManualSource
        }
        try scope.validate()
        try body.validate()
        try mediaManifest.validate()
        self.source = source
        self.scope = scope
        self.body = body
        self.mediaManifest = mediaManifest
    }
}

enum ServiceRequestManualDecisionV1: Equatable, Sendable {
    case needsTriage
    case disposition(
        ServiceRequestImportDispositionV1,
        selectedDuplicate: ServiceRequestRevisionReferenceV1?,
        reason: String?
    )
}

struct ServiceRequestManualPreviewV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let expectedRevision: WorkspaceExpectedRevisionV1
    let record: ServiceRequestRecordV1
    let dispositionEvent: ServiceRequestDispositionEventV1?
    let duplicateProjection: ServiceRequestDuplicateProjectionV1
    let mutationID: MutationIDV1
    let zeroWrite: Bool
    let previewSHA256: String

    init(
        workspaceID: WorkspaceID,
        expectedRevision: WorkspaceExpectedRevisionV1,
        record: ServiceRequestRecordV1,
        dispositionEvent: ServiceRequestDispositionEventV1?,
        duplicateProjection: ServiceRequestDuplicateProjectionV1,
        mutationID: MutationIDV1
    ) throws {
        try record.validate()
        try dispositionEvent?.validate()
        try duplicateProjection.validate()
        guard expectedRevision.workspaceID == workspaceID,
              record.workspaceID == workspaceID,
              record.source != .portableSubmission,
              record.submissionPublicID == nil,
              record.invitationPublicID == nil,
              record.acceptedSourceBytes == nil,
              record.capabilityAssessment.proofValidity == .unavailable,
              record.capabilityAssessment.importEligibility == .unavailable,
              record.mutationID == mutationID,
              duplicateProjection.basisRequestSHA256 == record.recordSHA256,
              duplicateProjection.candidates.allSatisfy({ candidate in
                  candidate.sharedSiteID == record.scope.siteID
                      && (candidate.sharedAssetID.map { assetID in
                          record.scope.assets.contains(where: { $0.assetID == assetID })
                      } ?? true)
              }) else {
            throw ServiceRequestWorkflowFailureV1.invalidContext
        }
        if let dispositionEvent {
            guard dispositionEvent.workspaceID == workspaceID,
                  dispositionEvent.request == (try record.reference),
                  dispositionEvent.mutationID == mutationID,
                  dispositionEvent.duplicateRecord.map({ selected in
                      duplicateProjection.candidates.contains(where: { $0.record == selected })
                  }) ?? true else {
                throw ServiceRequestWorkflowFailureV1.invalidContext
            }
        }
        self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision
        self.record = record
        self.dispositionEvent = dispositionEvent
        self.duplicateProjection = duplicateProjection
        self.mutationID = mutationID
        zeroWrite = true
        previewSHA256 = try ServiceRequestCanonicalCodecV1.sha256(
            Basis(
                workspaceID: workspaceID,
                expectedRevision: expectedRevision,
                record: record,
                dispositionEvent: dispositionEvent,
                duplicateProjection: duplicateProjection,
                mutationID: mutationID,
                zeroWrite: true
            )
        )
    }

    func validate() throws {
        let rebuilt = try Self(
            workspaceID: workspaceID,
            expectedRevision: expectedRevision,
            record: record,
            dispositionEvent: dispositionEvent,
            duplicateProjection: duplicateProjection,
            mutationID: mutationID
        )
        guard zeroWrite, previewSHA256 == rebuilt.previewSHA256 else {
            throw ServiceRequestWorkflowFailureV1.stalePreview
        }
    }

    private struct Basis: Codable {
        let workspaceID: WorkspaceID
        let expectedRevision: WorkspaceExpectedRevisionV1
        let record: ServiceRequestRecordV1
        let dispositionEvent: ServiceRequestDispositionEventV1?
        let duplicateProjection: ServiceRequestDuplicateProjectionV1
        let mutationID: MutationIDV1
        let zeroWrite: Bool
    }
}

struct ServiceRequestManualReceiptV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let mutationID: MutationIDV1
    let previewSHA256: String
    let resultingRecord: ServiceRequestRevisionReferenceV1
    let resultingState: ServiceRequestStateV1
    let canonicalMutationReceiptSHA256: String
    let receiptSHA256: String

    init(
        preview: ServiceRequestManualPreviewV1,
        canonicalMutationReceiptSHA256: String
    ) throws {
        try preview.validate()
        try ServiceRequestLimitsV1.digest(canonicalMutationReceiptSHA256)
        workspaceID = preview.workspaceID
        mutationID = preview.mutationID
        previewSHA256 = preview.previewSHA256
        resultingRecord = try preview.record.reference
        resultingState = preview.dispositionEvent?.resultingState ?? .openUntriaged
        self.canonicalMutationReceiptSHA256 = canonicalMutationReceiptSHA256
        receiptSHA256 = try ServiceRequestCanonicalCodecV1.sha256(
            Basis(
                workspaceID: workspaceID,
                mutationID: mutationID,
                previewSHA256: previewSHA256,
                resultingRecord: resultingRecord,
                resultingState: resultingState,
                canonicalMutationReceiptSHA256: canonicalMutationReceiptSHA256
            )
        )
    }

    func validate() throws {
        try resultingRecord.validate()
        try [previewSHA256, canonicalMutationReceiptSHA256, receiptSHA256]
            .forEach(ServiceRequestLimitsV1.digest)
        guard receiptSHA256 == (try ServiceRequestCanonicalCodecV1.sha256(
            Basis(
                workspaceID: workspaceID,
                mutationID: mutationID,
                previewSHA256: previewSHA256,
                resultingRecord: resultingRecord,
                resultingState: resultingState,
                canonicalMutationReceiptSHA256: canonicalMutationReceiptSHA256
            )
        )) else { throw ServiceRequestWorkflowFailureV1.receiptMismatch }
    }

    private struct Basis: Codable {
        let workspaceID: WorkspaceID
        let mutationID: MutationIDV1
        let previewSHA256: String
        let resultingRecord: ServiceRequestRevisionReferenceV1
        let resultingState: ServiceRequestStateV1
        let canonicalMutationReceiptSHA256: String
    }
}

struct ServiceRequestDispositionPlanV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let expectedRevision: WorkspaceExpectedRevisionV1
    let event: ServiceRequestDispositionEventV1
    let zeroWrite: Bool
    let planSHA256: String

    init(
        workspaceID: WorkspaceID,
        expectedRevision: WorkspaceExpectedRevisionV1,
        event: ServiceRequestDispositionEventV1
    ) throws {
        try event.validate()
        guard expectedRevision.workspaceID == workspaceID,
              event.workspaceID == workspaceID else {
            throw ServiceRequestWorkflowFailureV1.invalidContext
        }
        self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision
        self.event = event
        zeroWrite = true
        planSHA256 = try ServiceRequestCanonicalCodecV1.sha256(
            Basis(
                workspaceID: workspaceID,
                expectedRevision: expectedRevision,
                event: event,
                zeroWrite: true
            )
        )
    }

    func validate() throws {
        let rebuilt = try Self(
            workspaceID: workspaceID,
            expectedRevision: expectedRevision,
            event: event
        )
        guard zeroWrite, rebuilt.planSHA256 == planSHA256 else {
            throw ServiceRequestWorkflowFailureV1.stalePreview
        }
    }

    private struct Basis: Codable {
        let workspaceID: WorkspaceID
        let expectedRevision: WorkspaceExpectedRevisionV1
        let event: ServiceRequestDispositionEventV1
        let zeroWrite: Bool
    }
}

struct ServiceRequestDispositionReceiptV1: Equatable, Sendable {
    let plan: ServiceRequestDispositionPlanV1
    let canonicalMutationReceiptSHA256: String
}

struct ServiceRequestNeedsTriageItemV1: Equatable, Hashable, Sendable {
    let request: ServiceRequestRevisionReferenceV1
    let source: ServiceRequestSourceKindV1
    let siteID: UUID
    let assetIDs: [UUID]
    let searchableText: String
    let recordedAt: Date
}

struct ServiceRequestNeedsTriageProjectionV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let items: [ServiceRequestNeedsTriageItemV1]
    let derived: Bool
    let rebuildable: Bool
}

struct ServiceRequestWorkflowClaimsV1: Equatable, Sendable {
    let deliveryClaimed = false
    let requesterIdentityVerified = false
    let urgencyVerified = false
    let duplicateAutomaticallyMerged = false
    let workAutomaticallyCreated = false
    let dispatchClaimed = false
    let serviceLevelPromised = false
    let portalAvailable = false
    let emergencyIntakeClaimed = false
    let telemetryWritten = false
}

struct ServiceRequestStatusArtifactV1: Codable, Equatable, Sendable {
    let request: ServiceRequestRevisionReferenceV1
    let state: ServiceRequestStateV1
    let title: String
    let statusText: String
    let customerNote: String?
    let textLines: [String]
    let generatedAt: Date
    let deliveryClaimed: Bool
    let requesterIdentityVerified: Bool
    let urgencyVerified: Bool
    let artifactSHA256: String

    init(
        projection: ServiceRequestStateProjectionV1,
        customerNote: String? = nil,
        generatedAt: Date
    ) throws {
        try projection.validate()
        if let customerNote {
            try ServiceRequestLimitsV1.text(
                customerNote,
                maximumBytes: ServiceRequestLimitsV1.maximumReasonBytes
            )
        }
        guard generatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ServiceRequestWorkflowFailureV1.invalidContext
        }
        request = projection.request
        state = projection.state
        title = "Service request status"
        statusText = Self.text(for: projection.state)
        self.customerNote = customerNote
        textLines = [title, statusText] + (customerNote.map { [$0] } ?? [])
        self.generatedAt = generatedAt
        deliveryClaimed = false
        requesterIdentityVerified = false
        urgencyVerified = false
        artifactSHA256 = try ServiceRequestCanonicalCodecV1.sha256(
            Basis(
                request: request,
                state: state,
                title: title,
                statusText: statusText,
                customerNote: customerNote,
                textLines: textLines,
                generatedAt: generatedAt,
                deliveryClaimed: false,
                requesterIdentityVerified: false,
                urgencyVerified: false
            )
        )
    }

    func validate() throws {
        try request.validate()
        try ServiceRequestLimitsV1.digest(artifactSHA256)
        if let customerNote {
            try ServiceRequestLimitsV1.text(
                customerNote,
                maximumBytes: ServiceRequestLimitsV1.maximumReasonBytes
            )
        }
        guard generatedAt.timeIntervalSinceReferenceDate.isFinite,
              title == "Service request status",
              statusText == Self.text(for: state),
              textLines == [title, statusText] + (customerNote.map { [$0] } ?? []),
              !deliveryClaimed,
              !requesterIdentityVerified,
              !urgencyVerified,
              artifactSHA256 == (try ServiceRequestCanonicalCodecV1.sha256(
                Basis(
                    request: request,
                    state: state,
                    title: title,
                    statusText: statusText,
                    customerNote: customerNote,
                    textLines: textLines,
                    generatedAt: generatedAt,
                    deliveryClaimed: false,
                    requesterIdentityVerified: false,
                    urgencyVerified: false
                )
              )) else {
            throw ServiceRequestWorkflowFailureV1.invalidContext
        }
    }

    private static func text(for state: ServiceRequestStateV1) -> String {
        switch state {
        case .openUntriaged: return "Received; review has not been completed."
        case .openAccepted: return "Accepted for review."
        case .handledByLinkedWork: return "Linked work has been recorded."
        case .declined: return "Declined."
        case .closedNoWork: return "Closed without linked work."
        case .superseded: return "Superseded by a later record."
        }
    }

    private struct Basis: Codable {
        let request: ServiceRequestRevisionReferenceV1
        let state: ServiceRequestStateV1
        let title: String
        let statusText: String
        let customerNote: String?
        let textLines: [String]
        let generatedAt: Date
        let deliveryClaimed: Bool
        let requesterIdentityVerified: Bool
        let urgencyVerified: Bool
    }
}

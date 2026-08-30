import Foundation

enum ServiceRequestCoordinatorFailureV1: Error, Equatable, Sendable {
    case invalidPreview
    case capabilityRejected
    case duplicateDecisionMismatch
    case receiptMismatch
    case contactPromotionUnavailable
    case statusHandoffInvalid
}

private enum ServiceRequestCoordinatorClosedCodingV1 {
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
        init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
    }

    static func requireExact<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        _ keys: Key.Type
    ) throws where Key.AllCases: Collection {
        let actual = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
        let expected = Set(Key.allCases.map(\.stringValue))
        guard actual == expected else { throw ServiceRequestFailureV1.unknownKey }
    }

    static func validate(_ value: WorkspaceExpectedRevisionV1) throws {
        _ = try WorkspaceExpectedRevisionV1(
            workspaceID: value.workspaceID,
            generationID: value.generationID,
            writerInstanceID: value.writerInstanceID,
            workspaceRevision: value.workspaceRevision,
            entityRevisions: value.entityRevisions
        )
    }
}

@MainActor
protocol ServiceRequestDuplicateProjectingV1: AnyObject {
    func projectCandidates(
        workspaceID: WorkspaceID,
        submission: PortableServiceRequestSubmissionV1,
        canonicalSourceSHA256: String
    ) throws -> ServiceRequestDuplicateProjectionV1
}

/// C46 remains the owner of contact creation and purpose separation. C52 can
/// ask for a zero-write operational preview, but cannot promote the requester's
/// self-asserted value itself.
@MainActor
protocol ServiceRequestContactPromotionPreviewingV1: AnyObject {
    func previewOperationalContactPromotion(
        request: ServiceRequestRecordV1,
        party: ServicePartyReferenceV1
    ) throws -> ServiceRequestContactPromotionPreviewV1
}

struct ServiceRequestImportPreviewV1: Equatable, Sendable {
    let plan: ServiceRequestImportPlanV1
    let expectedRevision: WorkspaceExpectedRevisionV1
    let submission: PortableServiceRequestSubmissionV1
    let canonicalSourceBytes: CanonicalServiceRequestSourceBytesV1
    let capability: ServiceRequestSubmissionCapabilityV1
    let proposedRecord: ServiceRequestRecordV1?
    let proposedDispositionEvent: ServiceRequestDispositionEventV1?
    let receiptID: UUID

    init(
        plan: ServiceRequestImportPlanV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        submission: PortableServiceRequestSubmissionV1,
        canonicalSourceBytes: CanonicalServiceRequestSourceBytesV1,
        capability: ServiceRequestSubmissionCapabilityV1,
        proposedRecord: ServiceRequestRecordV1?,
        proposedDispositionEvent: ServiceRequestDispositionEventV1?,
        receiptID: UUID
    ) throws {
        let writesCanonical = Self.writesCanonical(plan.disposition)
        let proposedReference = try proposedRecord?.reference
        try ServiceRequestCoordinatorClosedCodingV1.validate(expectedRevision)
        try ServiceRequestLimitsV1.id(receiptID)
        try submission.validate()
        try canonicalSourceBytes.validate()
        guard plan.zeroWrite,
              expectedRevision.workspaceID == plan.workspaceID,
              expectedRevision.workspaceRevision == plan.basisWorkspaceRevision,
              submission.submissionPublicID == plan.submissionPublicID,
              canonicalSourceBytes.sha256 == plan.canonicalSourceSHA256,
              writesCanonical == (proposedRecord != nil),
              writesCanonical == (proposedDispositionEvent != nil) else {
            throw ServiceRequestCoordinatorFailureV1.invalidPreview
        }
        if let proposedRecord, let proposedDispositionEvent {
            guard proposedRecord.workspaceID == plan.workspaceID,
                  proposedRecord.submissionPublicID == plan.submissionPublicID,
                  proposedRecord.acceptedSourceBytes?.sha256 == plan.canonicalSourceSHA256,
                  proposedReference == proposedDispositionEvent.request,
                  proposedRecord.mutationID == plan.mutationID,
                  proposedDispositionEvent.mutationID == plan.mutationID,
                  proposedDispositionEvent.disposition == plan.disposition else {
                throw ServiceRequestCoordinatorFailureV1.invalidPreview
            }
            let mutation = try ServiceRequestMutationV1(
                workspaceID: plan.workspaceID,
                expectedRevision: expectedRevision,
                mutationID: plan.mutationID,
                payloads: [
                    .appendRecord(proposedRecord),
                    .appendDisposition(proposedDispositionEvent)
                ]
            )
            try mutation.validateForCanonicalWriter()
        }
        self.plan = plan
        self.expectedRevision = expectedRevision
        self.submission = submission
        self.canonicalSourceBytes = canonicalSourceBytes
        self.capability = capability
        self.proposedRecord = proposedRecord
        self.proposedDispositionEvent = proposedDispositionEvent
        self.receiptID = receiptID
    }

    static func writesCanonical(_ disposition: ServiceRequestImportDispositionV1) -> Bool {
        switch disposition {
        case .acceptAsNew, .acceptAndLinkDuplicate, .declineWithReason, .recordHistoryOnly:
            return true
        case .keepQuarantined, .discardUnimported:
            return false
        }
    }
}

struct ServiceRequestCanonicalWorkPreviewV1: Codable, Equatable, Hashable, Sendable {
    let target: WorkSubjectReferenceV1
    let choice: ServiceRequestWorkChoiceV1
    let canonicalWorkID: UUID
    let canonicalWorkRevision: UInt64
    let canonicalWorkSHA256: String

    init(
        target: WorkSubjectReferenceV1,
        choice: ServiceRequestWorkChoiceV1,
        canonicalWorkID: UUID,
        canonicalWorkRevision: UInt64,
        canonicalWorkSHA256: String
    ) throws {
        self.target = target
        self.choice = choice
        self.canonicalWorkID = canonicalWorkID
        self.canonicalWorkRevision = canonicalWorkRevision
        self.canonicalWorkSHA256 = canonicalWorkSHA256
        try validate()
    }

    func validate() throws {
        try target.validate()
        try ServiceRequestLimitsV1.id(canonicalWorkID)
        try ServiceRequestLimitsV1.digest(canonicalWorkSHA256)
        guard canonicalWorkRevision > 0 else { throw ServiceRequestFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case target, choice, canonicalWorkID, canonicalWorkRevision, canonicalWorkSHA256
    }

    init(from decoder: Decoder) throws {
        try ServiceRequestCoordinatorClosedCodingV1.requireExact(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            target: container.decode(WorkSubjectReferenceV1.self, forKey: .target),
            choice: container.decode(ServiceRequestWorkChoiceV1.self, forKey: .choice),
            canonicalWorkID: container.decode(UUID.self, forKey: .canonicalWorkID),
            canonicalWorkRevision: container.decode(UInt64.self, forKey: .canonicalWorkRevision),
            canonicalWorkSHA256: container.decode(String.self, forKey: .canonicalWorkSHA256)
        )
    }
}

struct ServiceRequestWorkConversionPlanV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let expectedRevision: WorkspaceExpectedRevisionV1
    let event: ServiceRequestWorkLinkEventV1
    let zeroWrite: Bool
    let planSHA256: String

    init(
        workspaceID: WorkspaceID,
        expectedRevision: WorkspaceExpectedRevisionV1,
        event: ServiceRequestWorkLinkEventV1
    ) throws {
        try event.validate()
        try ServiceRequestCoordinatorClosedCodingV1.validate(expectedRevision)
        guard event.workspaceID == workspaceID,
              expectedRevision.workspaceID == workspaceID else {
            throw ServiceRequestFailureV1.scopeMismatch
        }
        self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision
        self.event = event
        zeroWrite = true
        planSHA256 = try ServiceRequestCanonicalCodecV1.sha256(
            Basis(workspaceID: workspaceID, expectedRevision: expectedRevision, event: event, zeroWrite: true)
        )
        let payload: ServiceRequestMutationPayloadV1 = event.kind == .link
            ? .appendWorkLink(event)
            : .appendWorkLinkReversal(event)
        try ServiceRequestMutationV1(
            workspaceID: workspaceID,
            expectedRevision: expectedRevision,
            mutationID: event.mutationID,
            payloads: [payload]
        ).validateForCanonicalWriter()
    }

    func validate() throws {
        try event.validate()
        try ServiceRequestCoordinatorClosedCodingV1.validate(expectedRevision)
        try ServiceRequestLimitsV1.digest(planSHA256)
        guard event.workspaceID == workspaceID,
              zeroWrite,
              planSHA256 == (try ServiceRequestCanonicalCodecV1.sha256(
                Basis(
                    workspaceID: workspaceID,
                    expectedRevision: expectedRevision,
                    event: event,
                    zeroWrite: true
                )
              )) else {
            throw ServiceRequestCoordinatorFailureV1.invalidPreview
        }
        let payload: ServiceRequestMutationPayloadV1 = event.kind == .link
            ? .appendWorkLink(event)
            : .appendWorkLinkReversal(event)
        try ServiceRequestMutationV1(
            workspaceID: workspaceID,
            expectedRevision: expectedRevision,
            mutationID: event.mutationID,
            payloads: [payload]
        ).validateForCanonicalWriter()
    }

    private struct Basis: Codable {
        let workspaceID: WorkspaceID
        let expectedRevision: WorkspaceExpectedRevisionV1
        let event: ServiceRequestWorkLinkEventV1
        let zeroWrite: Bool
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case workspaceID, expectedRevision, event, zeroWrite, planSHA256
    }

    init(from decoder: Decoder) throws {
        try ServiceRequestCoordinatorClosedCodingV1.requireExact(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rebuilt = try Self(
            workspaceID: container.decode(WorkspaceID.self, forKey: .workspaceID),
            expectedRevision: container.decode(
                WorkspaceExpectedRevisionV1.self,
                forKey: .expectedRevision
            ),
            event: container.decode(ServiceRequestWorkLinkEventV1.self, forKey: .event)
        )
        guard try container.decode(Bool.self, forKey: .zeroWrite) == rebuilt.zeroWrite,
              try container.decode(String.self, forKey: .planSHA256) == rebuilt.planSHA256 else {
            throw ServiceRequestFailureV1.invalidDigest
        }
        self = rebuilt
    }
}

struct ServiceRequestWorkConversionReceiptV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let mutationID: MutationIDV1
    let planSHA256: String
    let event: ServiceRequestWorkLinkEventV1
    let canonicalMutationReceiptSHA256: String
    let receiptSHA256: String

    init(
        plan: ServiceRequestWorkConversionPlanV1,
        canonicalMutationReceiptSHA256: String
    ) throws {
        try ServiceRequestLimitsV1.digest(plan.planSHA256)
        try ServiceRequestLimitsV1.digest(canonicalMutationReceiptSHA256)
        workspaceID = plan.workspaceID
        mutationID = plan.event.mutationID
        planSHA256 = plan.planSHA256
        event = plan.event
        self.canonicalMutationReceiptSHA256 = canonicalMutationReceiptSHA256
        receiptSHA256 = try ServiceRequestCanonicalCodecV1.sha256(
            Basis(
                workspaceID: plan.workspaceID,
                mutationID: plan.event.mutationID,
                planSHA256: plan.planSHA256,
                event: plan.event,
                canonicalMutationReceiptSHA256: canonicalMutationReceiptSHA256
            )
        )
    }

    func validate() throws {
        try event.validate()
        try ServiceRequestLimitsV1.digest(planSHA256)
        try ServiceRequestLimitsV1.digest(canonicalMutationReceiptSHA256)
        try ServiceRequestLimitsV1.digest(receiptSHA256)
        guard event.workspaceID == workspaceID,
              event.mutationID == mutationID,
              receiptSHA256 == (try ServiceRequestCanonicalCodecV1.sha256(
                Basis(
                    workspaceID: workspaceID,
                    mutationID: mutationID,
                    planSHA256: planSHA256,
                    event: event,
                    canonicalMutationReceiptSHA256: canonicalMutationReceiptSHA256
                )
              )) else {
            throw ServiceRequestCoordinatorFailureV1.receiptMismatch
        }
    }

    private struct Basis: Codable {
        let workspaceID: WorkspaceID
        let mutationID: MutationIDV1
        let planSHA256: String
        let event: ServiceRequestWorkLinkEventV1
        let canonicalMutationReceiptSHA256: String
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case workspaceID, mutationID, planSHA256, event
        case canonicalMutationReceiptSHA256, receiptSHA256
    }

    init(from decoder: Decoder) throws {
        try ServiceRequestCoordinatorClosedCodingV1.requireExact(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceID = try container.decode(WorkspaceID.self, forKey: .workspaceID)
        mutationID = try container.decode(MutationIDV1.self, forKey: .mutationID)
        planSHA256 = try container.decode(String.self, forKey: .planSHA256)
        event = try container.decode(ServiceRequestWorkLinkEventV1.self, forKey: .event)
        canonicalMutationReceiptSHA256 = try container.decode(
            String.self,
            forKey: .canonicalMutationReceiptSHA256
        )
        receiptSHA256 = try container.decode(String.self, forKey: .receiptSHA256)
        try validate()
    }
}

struct ServiceRequestContactPromotionPreviewV1: Equatable, Sendable {
    let request: ServiceRequestRevisionReferenceV1
    let party: ServicePartyReferenceV1
    let assertedValue: String
    let suggestedKind: ServiceContactKindV1
    let purpose: String
    let zeroWrite: Bool

    init(
        request: ServiceRequestRevisionReferenceV1,
        party: ServicePartyReferenceV1,
        assertedValue: String,
        suggestedKind: ServiceContactKindV1
    ) throws {
        try party.validate()
        try OperationalContactValidationV1.contactValue(assertedValue, kind: suggestedKind)
        self.request = request
        self.party = party
        self.assertedValue = assertedValue
        self.suggestedKind = suggestedKind
        purpose = "OPERATIONAL_CONTACT_ONLY"
        zeroWrite = true
    }
}

/// A generated status artifact reports only canonical request state. Passing it
/// to the existing C46 handoff route does not claim delivery or recipient
/// identity, and no service-request coordinator performs the OS handoff.
struct ServiceRequestStatusArtifactHandoffV1: Codable, Equatable, Sendable {
    let projection: ServiceRequestStateProjectionV1
    let handoffIntent: SystemHandoffIntentV1
    let generatedAt: Date
    let requesterIdentityVerified: Bool
    let deliveryClaimed: Bool
    let artifactSHA256: String

    init(
        projection: ServiceRequestStateProjectionV1,
        handoffIntent: SystemHandoffIntentV1,
        generatedAt: Date
    ) throws {
        try handoffIntent.validate()
        guard handoffIntent.target.kind == .serviceContactPoint,
              generatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ServiceRequestCoordinatorFailureV1.statusHandoffInvalid
        }
        self.projection = projection
        self.handoffIntent = handoffIntent
        self.generatedAt = generatedAt
        requesterIdentityVerified = false
        deliveryClaimed = false
        artifactSHA256 = try ServiceRequestCanonicalCodecV1.sha256(
            Basis(
                projection: projection,
                handoffIntent: handoffIntent,
                generatedAt: generatedAt,
                requesterIdentityVerified: false,
                deliveryClaimed: false
            )
        )
    }

    func validate() throws {
        try handoffIntent.validate()
        try ServiceRequestLimitsV1.digest(artifactSHA256)
        guard handoffIntent.target.kind == .serviceContactPoint,
              generatedAt.timeIntervalSinceReferenceDate.isFinite,
              !requesterIdentityVerified,
              !deliveryClaimed,
              artifactSHA256 == (try ServiceRequestCanonicalCodecV1.sha256(
                Basis(
                    projection: projection,
                    handoffIntent: handoffIntent,
                    generatedAt: generatedAt,
                    requesterIdentityVerified: false,
                    deliveryClaimed: false
                )
              )) else {
            throw ServiceRequestCoordinatorFailureV1.statusHandoffInvalid
        }
    }

    private struct Basis: Codable {
        let projection: ServiceRequestStateProjectionV1
        let handoffIntent: SystemHandoffIntentV1
        let generatedAt: Date
        let requesterIdentityVerified: Bool
        let deliveryClaimed: Bool
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case projection, handoffIntent, generatedAt
        case requesterIdentityVerified, deliveryClaimed, artifactSHA256
    }

    init(from decoder: Decoder) throws {
        try ServiceRequestCoordinatorClosedCodingV1.requireExact(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rebuilt = try Self(
            projection: container.decode(ServiceRequestStateProjectionV1.self, forKey: .projection),
            handoffIntent: container.decode(SystemHandoffIntentV1.self, forKey: .handoffIntent),
            generatedAt: container.decode(Date.self, forKey: .generatedAt)
        )
        guard try container.decode(
                Bool.self,
                forKey: .requesterIdentityVerified
              ) == rebuilt.requesterIdentityVerified,
              try container.decode(Bool.self, forKey: .deliveryClaimed) == rebuilt.deliveryClaimed,
              try container.decode(String.self, forKey: .artifactSHA256) == rebuilt.artifactSHA256 else {
            throw ServiceRequestFailureV1.invalidDigest
        }
        self = rebuilt
    }
}

@MainActor
final class ServiceRequestCoordinatorV1 {
    private let duplicates: any ServiceRequestDuplicateProjectingV1
    private let writer: WorkspaceWriterV1
    private let lifecycle: ServiceRequestLifecycleAdapterV1
    private let contactPromotion: any ServiceRequestContactPromotionPreviewingV1
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource

    init(
        duplicates: any ServiceRequestDuplicateProjectingV1,
        writer: WorkspaceWriterV1,
        lifecycle: ServiceRequestLifecycleAdapterV1,
        contactPromotion: any ServiceRequestContactPromotionPreviewingV1,
        clock: any ApplicationClock,
        idSource: any ApplicationIDSource
    ) {
        self.duplicates = duplicates
        self.writer = writer
        self.lifecycle = lifecycle
        self.contactPromotion = contactPromotion
        self.clock = clock
        self.idSource = idSource
    }

    func previewPortableImport(
        expectedRevision: WorkspaceExpectedRevisionV1,
        release: PortableServiceRequestProtocolReleaseV1,
        invitation: PortableServiceRequestInvitationV1,
        submission: PortableServiceRequestSubmissionV1,
        canonicalSourceBytes: CanonicalServiceRequestSourceBytesV1,
        disposition: ServiceRequestImportDispositionV1,
        selectedDuplicate: ServiceRequestRevisionReferenceV1?,
        reason: String?,
        mutationID: MutationIDV1
    ) async throws -> ServiceRequestImportPreviewV1 {
        let workspaceID = expectedRevision.workspaceID
        try release.validate()
        try invitation.manifest.validate()
        try submission.validate()
        try canonicalSourceBytes.validate()
        guard invitation.manifest.protocolReleaseSHA256 == release.releaseSHA256,
              submission.protocolReleaseSHA256 == release.releaseSHA256,
              submission.invitationPublicID == invitation.manifest.invitationPublicID,
              submission.invitationManifestSHA256 == invitation.manifest.manifestSHA256,
              submission.frozenScopeSHA256 == invitation.manifest.scope.scopeSHA256 else {
            throw ServiceRequestCoordinatorFailureV1.invalidPreview
        }
        let capability = try invitation.capability
        let lifecyclePreview = try await lifecycle.previewSubmission(
            submission,
            sourceBytes: canonicalSourceBytes.bytes,
            capability: capability
        )
        guard lifecyclePreview.invitationPublicID == submission.invitationPublicID,
              lifecyclePreview.submissionPublicID == submission.submissionPublicID,
              lifecyclePreview.canonicalSourceSHA256 == canonicalSourceBytes.sha256 else {
            throw ServiceRequestCoordinatorFailureV1.invalidPreview
        }
        let assessment = lifecyclePreview.capabilityAssessment
        let requiresEligibleCapability = disposition == .acceptAsNew
            || disposition == .acceptAndLinkDuplicate
        guard !requiresEligibleCapability || (
            assessment.proofValidity == .valid
                && assessment.importEligibility == .eligible
        ) else {
            throw ServiceRequestCoordinatorFailureV1.capabilityRejected
        }
        let duplicateProjection = try duplicates.projectCandidates(
            workspaceID: workspaceID,
            submission: submission,
            canonicalSourceSHA256: canonicalSourceBytes.sha256
        )
        let selectedIsCandidate = selectedDuplicate.map { selected in
            duplicateProjection.candidates.contains(where: { $0.record == selected })
        } ?? false
        guard (disposition == .acceptAndLinkDuplicate) == (selectedDuplicate != nil),
              disposition != .acceptAndLinkDuplicate || selectedIsCandidate,
              (disposition == .declineWithReason) == (reason?.isEmpty == false) else {
            throw ServiceRequestCoordinatorFailureV1.duplicateDecisionMismatch
        }
        let plan = try ServiceRequestImportPlanV1(
            workspaceID: workspaceID,
            basisWorkspaceRevision: expectedRevision.workspaceRevision,
            submissionPublicID: submission.submissionPublicID,
            canonicalSourceSHA256: canonicalSourceBytes.sha256,
            capabilityAssessment: assessment,
            duplicateProjection: duplicateProjection,
            disposition: disposition,
            selectedDuplicate: selectedDuplicate,
            mutationID: mutationID
        )
        guard ServiceRequestImportPreviewV1.writesCanonical(disposition) else {
            return try ServiceRequestImportPreviewV1(
                plan: plan,
                expectedRevision: expectedRevision,
                submission: submission,
                canonicalSourceBytes: canonicalSourceBytes,
                capability: capability,
                proposedRecord: nil,
                proposedDispositionEvent: nil,
                receiptID: mutationID.rawValue
            )
        }
        let recordedAt = clock.now()
        let record = try ServiceRequestRecordV1(
            recordID: idSource.makeID(),
            workspaceID: workspaceID,
            submissionPublicID: submission.submissionPublicID,
            invitationPublicID: submission.invitationPublicID,
            source: .portableSubmission,
            scope: invitation.manifest.scope,
            body: submission.body,
            mediaManifest: submission.mediaManifest,
            acceptedSourceBytes: canonicalSourceBytes,
            capabilityAssessment: assessment,
            revision: 1,
            mutationID: mutationID,
            recordedAt: recordedAt
        )
        let event = try ServiceRequestDispositionEventV1(
            eventID: idSource.makeID(),
            workspaceID: workspaceID,
            request: record.reference,
            disposition: disposition,
            resultingState: Self.state(for: disposition),
            reason: reason,
            duplicateRecord: selectedDuplicate,
            revision: 1,
            mutationID: mutationID,
            recordedAt: recordedAt
        )
        let scopedExpectedRevision = try Self.scopedExpectedRevision(
            expectedRevision,
            payloads: [.appendRecord(record), .appendDisposition(event)]
        )
        return try ServiceRequestImportPreviewV1(
            plan: plan,
            expectedRevision: scopedExpectedRevision,
            submission: submission,
            canonicalSourceBytes: canonicalSourceBytes,
            capability: capability,
            proposedRecord: record,
            proposedDispositionEvent: event,
            receiptID: mutationID.rawValue
        )
    }

    func commitImport(_ preview: ServiceRequestImportPreviewV1) async throws -> ServiceRequestImportReceiptV1 {
        let receipt: ServiceRequestImportReceiptV1
        if let record = preview.proposedRecord,
           let disposition = preview.proposedDispositionEvent {
            let mutation = try ServiceRequestMutationV1(
                workspaceID: preview.plan.workspaceID,
                expectedRevision: preview.expectedRevision,
                mutationID: preview.plan.mutationID,
                payloads: [.appendRecord(record), .appendDisposition(disposition)]
            )
            let canonical = try writer.durableServiceRequestReceipt(mutation: mutation)
                ?? writer.commitServiceRequest(mutation)
            receipt = try Self.importReceipt(
                preview: preview,
                canonical: canonical,
                resultingRecord: record.reference
            )
            if preview.plan.disposition == .recordHistoryOnly {
                _ = try await lifecycle.applySubmission(
                    preview.submission,
                    sourceBytes: preview.canonicalSourceBytes.bytes,
                    disposition: .recordHistoryOnly,
                    capability: preview.capability,
                    operationID: preview.receiptID
                )
            } else {
                _ = try await lifecycle.prepareSubmission(
                    plan: preview.plan,
                    receipt: receipt,
                    submission: preview.submission,
                    sourceBytes: preview.canonicalSourceBytes.bytes,
                    capability: preview.capability
                )
                _ = try await lifecycle.finalizeSubmission(plan: preview.plan, receipt: receipt)
            }
        } else {
            _ = try await lifecycle.applySubmission(
                preview.submission,
                sourceBytes: preview.canonicalSourceBytes.bytes,
                disposition: preview.plan.disposition,
                capability: preview.capability,
                operationID: preview.receiptID
            )
            receipt = try ServiceRequestImportReceiptV1(
                receiptID: preview.receiptID,
                workspaceID: preview.plan.workspaceID,
                submissionPublicID: preview.plan.submissionPublicID,
                canonicalSourceSHA256: preview.plan.canonicalSourceSHA256,
                planSHA256: preview.plan.planSHA256,
                disposition: preview.plan.disposition,
                mutationID: preview.plan.mutationID,
                recordedAt: clock.now()
            )
        }
        try Self.validate(receipt, matches: preview)
        return receipt
    }

    func recoverImport(_ preview: ServiceRequestImportPreviewV1) async throws -> ServiceRequestImportReceiptV1 {
        try await commitImport(preview)
    }

    func previewWorkConversion(
        request: ServiceRequestRevisionReferenceV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        work: ServiceRequestCanonicalWorkPreviewV1,
        predecessor: ServiceRequestWorkLinkEventV1?,
        mutationID: MutationIDV1
    ) throws -> ServiceRequestWorkConversionPlanV1 {
        let workspaceID = expectedRevision.workspaceID
        try work.validate()
        guard predecessor == nil else { throw ServiceRequestCoordinatorFailureV1.invalidPreview }
        let event = try ServiceRequestWorkLinkEventV1(
            eventID: idSource.makeID(),
            workspaceID: workspaceID,
            request: request,
            target: work.target,
            choice: work.choice,
            canonicalWorkID: work.canonicalWorkID,
            canonicalWorkRevision: work.canonicalWorkRevision,
            canonicalWorkSHA256: work.canonicalWorkSHA256,
            kind: .link,
            predecessorEventID: nil,
            predecessorEventSHA256: nil,
            revision: 1,
            mutationID: mutationID,
            recordedAt: clock.now()
        )
        let scopedExpectedRevision = try Self.scopedExpectedRevision(
            expectedRevision,
            payloads: [.appendWorkLink(event)]
        )
        return try ServiceRequestWorkConversionPlanV1(
            workspaceID: workspaceID,
            expectedRevision: scopedExpectedRevision,
            event: event
        )
    }

    func previewWorkLinkReversal(
        predecessor: ServiceRequestWorkLinkEventV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    ) throws -> ServiceRequestWorkConversionPlanV1 {
        try predecessor.validate()
        guard predecessor.kind == .link,
              predecessor.revision < UInt64.max,
              expectedRevision.workspaceID == predecessor.workspaceID else {
            throw ServiceRequestCoordinatorFailureV1.invalidPreview
        }
        let event = try ServiceRequestWorkLinkEventV1(
            eventID: idSource.makeID(),
            workspaceID: predecessor.workspaceID,
            request: predecessor.request,
            target: predecessor.target,
            choice: predecessor.choice,
            canonicalWorkID: predecessor.canonicalWorkID,
            canonicalWorkRevision: predecessor.canonicalWorkRevision,
            canonicalWorkSHA256: predecessor.canonicalWorkSHA256,
            kind: .unlinkReversal,
            reversesEventID: predecessor.eventID,
            predecessorEventID: predecessor.eventID,
            predecessorEventSHA256: predecessor.eventSHA256,
            revision: predecessor.revision + 1,
            mutationID: mutationID,
            recordedAt: clock.now()
        )
        try event.validateSuccessor(of: predecessor)
        let scopedExpectedRevision = try Self.scopedExpectedRevision(
            expectedRevision,
            payloads: [.appendWorkLinkReversal(event)]
        )
        return try ServiceRequestWorkConversionPlanV1(
            workspaceID: predecessor.workspaceID,
            expectedRevision: scopedExpectedRevision,
            event: event
        )
    }

    func commitWorkConversion(
        _ plan: ServiceRequestWorkConversionPlanV1
    ) throws -> ServiceRequestWorkConversionReceiptV1 {
        try plan.validate()
        let payload: ServiceRequestMutationPayloadV1 = plan.event.kind == .link
            ? .appendWorkLink(plan.event)
            : .appendWorkLinkReversal(plan.event)
        let mutation = try ServiceRequestMutationV1(
            workspaceID: plan.workspaceID,
            expectedRevision: plan.expectedRevision,
            mutationID: plan.event.mutationID,
            payloads: [payload]
        )
        let canonical = try writer.durableServiceRequestReceipt(mutation: mutation)
            ?? writer.commitServiceRequest(mutation)
        let accepted = try ServiceRequestWorkConversionReceiptV1(
            plan: plan,
            canonicalMutationReceiptSHA256: WorkspaceMutationCanonicalV1.sha256(
                canonical.mutationReceipt
            )
        )
        try Self.validate(accepted, matches: plan)
        return accepted
    }

    func recoverWorkConversion(
        _ plan: ServiceRequestWorkConversionPlanV1
    ) throws -> ServiceRequestWorkConversionReceiptV1 {
        try commitWorkConversion(plan)
    }

    func previewContactPromotion(
        request: ServiceRequestRecordV1,
        party: ServicePartyReferenceV1
    ) throws -> ServiceRequestContactPromotionPreviewV1 {
        guard request.body.contact.value != nil else {
            throw ServiceRequestCoordinatorFailureV1.contactPromotionUnavailable
        }
        let preview = try contactPromotion.previewOperationalContactPromotion(
            request: request,
            party: party
        )
        guard preview.request == (try request.reference),
              preview.party == party,
              preview.zeroWrite,
              preview.purpose == "OPERATIONAL_CONTACT_ONLY" else {
            throw ServiceRequestCoordinatorFailureV1.receiptMismatch
        }
        return preview
    }

    func prepareStatusArtifactHandoff(
        projection: ServiceRequestStateProjectionV1,
        handoffIntent: SystemHandoffIntentV1
    ) throws -> ServiceRequestStatusArtifactHandoffV1 {
        try ServiceRequestStatusArtifactHandoffV1(
            projection: projection,
            handoffIntent: handoffIntent,
            generatedAt: clock.now()
        )
    }

    private static func state(for disposition: ServiceRequestImportDispositionV1) -> ServiceRequestStateV1 {
        switch disposition {
        case .acceptAsNew: return .openAccepted
        case .acceptAndLinkDuplicate: return .openAccepted
        case .recordHistoryOnly: return .closedNoWork
        case .declineWithReason: return .declined
        case .keepQuarantined, .discardUnimported: return .openUntriaged
        }
    }

    /// Narrows a writer-issued workspace snapshot to the exact identities that
    /// the now-materialized zero-write preview will mutate. New identities are
    /// valid only at revision zero; predecessor-backed payloads must match the
    /// revision already carried by the snapshot.
    private static func scopedExpectedRevision(
        _ source: WorkspaceExpectedRevisionV1,
        payloads: [ServiceRequestMutationPayloadV1]
    ) throws -> WorkspaceExpectedRevisionV1 {
        try ServiceRequestCoordinatorClosedCodingV1.validate(source)
        let known = Dictionary(
            uniqueKeysWithValues: source.entityRevisions.map { ($0.identity, $0.revision) }
        )
        let required = try payloads.map { payload in
            let identity = try payload.concurrencyIdentity
            let revision = payload.expectedEntityRevision
            guard known[identity, default: 0] == revision else {
                throw WorkspaceMutationFailureV1.staleWorkspaceRevision
            }
            return WorkspaceEntityRevisionV1(identity: identity, revision: revision)
        }
        return try WorkspaceExpectedRevisionV1(
            workspaceID: source.workspaceID,
            generationID: source.generationID,
            writerInstanceID: source.writerInstanceID,
            workspaceRevision: source.workspaceRevision,
            entityRevisions: required
        )
    }

    private static func validate(
        _ receipt: ServiceRequestImportReceiptV1,
        matches preview: ServiceRequestImportPreviewV1
    ) throws {
        let plan = preview.plan
        guard receipt.workspaceID == plan.workspaceID,
              receipt.receiptID == preview.receiptID,
              receipt.submissionPublicID == plan.submissionPublicID,
              receipt.canonicalSourceSHA256 == plan.canonicalSourceSHA256,
              receipt.planSHA256 == plan.planSHA256,
              receipt.disposition == plan.disposition,
              receipt.mutationID == plan.mutationID else {
            throw ServiceRequestCoordinatorFailureV1.receiptMismatch
        }
    }

    private static func importReceipt(
        preview: ServiceRequestImportPreviewV1,
        canonical: ServiceRequestMutationReceiptV1,
        resultingRecord: ServiceRequestRevisionReferenceV1
    ) throws -> ServiceRequestImportReceiptV1 {
        try ServiceRequestImportReceiptV1(
            receiptID: preview.receiptID,
            workspaceID: preview.plan.workspaceID,
            submissionPublicID: preview.plan.submissionPublicID,
            canonicalSourceSHA256: preview.plan.canonicalSourceSHA256,
            planSHA256: preview.plan.planSHA256,
            disposition: preview.plan.disposition,
            mutationID: preview.plan.mutationID,
            canonicalMutationReceiptSHA256: WorkspaceMutationCanonicalV1.sha256(
                canonical.mutationReceipt
            ),
            resultingRecord: resultingRecord,
            recordedAt: canonical.mutationReceipt.committedAt
        )
    }

    private static func validate(
        _ receipt: ServiceRequestWorkConversionReceiptV1,
        matches plan: ServiceRequestWorkConversionPlanV1
    ) throws {
        try plan.validate()
        try receipt.validate()
        guard receipt.workspaceID == plan.workspaceID,
              receipt.mutationID == plan.event.mutationID,
              receipt.planSHA256 == plan.planSHA256,
              receipt.event == plan.event else {
            throw ServiceRequestCoordinatorFailureV1.receiptMismatch
        }
    }
}

enum C52ServiceRequestCoordinatorBoundaryV1 {
    static let previewWritesWorkspace = false
    static let duplicateCandidatesAreSuggestionOnly = true
    static let dispositionIsExplicit = true
    static let workConversionUsesExactlyOnceMutationID = true
    static let reversalIsAppendOnly = true
    static let durableReceiptQueryPrecedesWrite = true
    static let effectBeforeReceiptRecoveryIsRequired = true
    static let contactPromotionDelegatesToC46 = true
    static let reviewCapabilityProofIsServiceAuthority = false
    static let createsPortalOrNetwork = false
    static let createsSecondStoreOrWriter = false
    static let automaticWorkCreation = false
    static let statusArtifactClaimsDelivery = false
}

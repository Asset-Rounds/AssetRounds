import CryptoKit
import Foundation

enum RecipientReviewWorkflowFailureV1: Error, Equatable, Sendable {
    case requestUnavailable
    case encryptionDisabled
    case encryptionUnavailable
    case unsupportedExchangeKind
    case cleartextWarningRequired
    case previewDecisionMismatch
}

enum RecipientReviewEncryptionAvailabilityV1: String, Codable, CaseIterable, Sendable {
    case disabled = "DISABLED"
    case unavailable = "UNAVAILABLE"
    case manualPassphraseAvailable = "MANUAL_PASSPHRASE_AVAILABLE"
}

enum RecipientReviewExchangeProtectionV1: String, Codable, CaseIterable, Sendable {
    case manualPassphraseEncryptedV1 = "MANUAL_PASSPHRASE_ENCRYPTED_V1"
    case legacyClearWithExplicitWarning = "LEGACY_CLEAR_WITH_EXPLICIT_WARNING"

    var displaysCleartextWarning: Bool {
        self == .legacyClearWithExplicitWarning
    }
}

struct RecipientReviewRequestReplayV1: Equatable, Sendable {
    let request: PortableExchangeReviewRequestBytesV2
    let protection: RecipientReviewExchangeProtectionV1
    let isOffline: Bool
    let entitlementRequired: Bool
    let isIsolatedFromNormalWorkspaces: Bool
}

struct RecipientReviewImportPreviewV1: Equatable, Sendable {
    let sessionPreview: PortableExchangeImportPreviewV2
    let canonicalPlan: ExternalReviewImportPlanV1
    let isZeroWrite: Bool
    let requiresExplicitDecision: Bool
}

struct RecipientReviewHistoryReceiptV1: Equatable, Sendable {
    let sessionID: UUID
    let state: PortableExchangeSessionStateV2
    let proofValidity: ReviewProofValidityV1
    let isVerifiedResponse: Bool
    let appliedToCanonicalWorkspace: Bool
}

struct RecipientReviewWorkflowContextV1: Equatable, Sendable {
    let requestPublicID: ReviewRequestPublicIDV1
    let sessionID: UUID?
    let requestManifest: ReviewRequestManifestV1?

    init(
        requestPublicID: ReviewRequestPublicIDV1,
        sessionID: UUID? = nil,
        requestManifest: ReviewRequestManifestV1? = nil
    ) throws {
        try requestPublicID.validate()
        if let requestManifest {
            try requestManifest.validate()
            guard requestManifest.requestPublicID == requestPublicID else {
                throw PortableReviewFailureV1.invalidValue
            }
        }
        self.requestPublicID = requestPublicID
        self.sessionID = sessionID
        self.requestManifest = requestManifest
    }
}

struct RecipientReviewWorkflowProjectionV1: Equatable, Sendable {
    let requestPublicID: ReviewRequestPublicIDV1
    let lifecycleState: PortableExchangeSessionStateV2?
    let hasReplayableManifest: Bool
    let hasReplayablePackage: Bool
    let canCreateResponse: Bool
    let encryptionAvailability: RecipientReviewEncryptionAvailabilityV1
    let clearExchangeRequiresVisibleWarning: Bool
    let previewWrites: Bool
    let recipientModeUsesNormalWorkspace: Bool
    let establishesIdentity: Bool
    let establishesDeliveryOrRead: Bool
}

struct RecipientReviewPreviewImportCommandV1: Sendable {
    let response: ReviewResponseEnvelopeV1
    let capability: BearerResponseCapabilityV1
    let responseRecord: ExternalReviewResponseRecordV1
    let mapping: ReviewRequestC14SubjectItemMappingV1
    let reviewID: UUID
    let basisWorkspaceRevision: UInt64
    let decision: ExternalReviewImportDecisionV1
    let mutationID: MutationIDV1
}

enum RecipientReviewWorkflowCommandV1: Sendable {
    case replayClearRequest(
        kind: PortableExchangeReviewRequestByteKindV2,
        userAcknowledgedCleartextWarning: Bool
    )
    case createResponse(
        capability: BearerResponseCapabilityV1,
        responsePublicID: String,
        body: ReviewResponseBodyV1
    )
    case previewImport(RecipientReviewPreviewImportCommandV1)
    case acceptAndApply(
        preview: RecipientReviewImportPreviewV1,
        mutation: InspectionReviewMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1
    )
    case finalizeSessionOnly(
        preview: RecipientReviewImportPreviewV1,
        receipt: ExternalReviewImportReceiptV1
    )
    case recordResponseReceivedElsewhere(OriginRecordedReviewResponseV1)
    case recoverAcceptAndApply(MutationIDV1)
    case openEncryptedRequest(EncryptedPortableEnvelopeOpenRequestV1)
    case sealEncryptedResponse(EncryptedPortableEnvelopeSealRequestV1)
    case protectEncryptedResponse(
        opening: EncryptedPortableEnvelopeOpenRequestV1,
        sealing: EncryptedPortableEnvelopeSealRequestV1
    )
    case readLegacyClear(
        source: any EncryptedEnvelopeBoundedSeekableSourceV1,
        kind: EncryptedPortableEnvelopeInnerKindV1,
        userAcknowledgedCleartextWarning: Bool
    )
}

enum RecipientReviewWorkflowCommandOutcomeV1: Sendable {
    case requestReplay(RecipientReviewRequestReplayV1)
    case responseCreated(ReviewResponseEnvelopeV1)
    case importPreview(RecipientReviewImportPreviewV1)
    case canonicalApplied(PortableReviewMutationReceiptV1)
    case sessionFinalized(ExternalReviewImportReceiptV1)
    case unverifiedHistoryRecorded(RecipientReviewHistoryReceiptV1)
    case recovered
    case encryptedRequestOpened(EncryptedPortableEnvelopeOpenOutcomeV1)
    case encryptedResponseSealed(EncryptedPortableEnvelopeSealOutcomeV1)
    case legacyClearRead(RecipientReviewExchangeProtectionV1)
}

enum RecipientReviewWorkflowClaimsV1 {
    static let operatesOffline = true
    static let requiresEntitlement = false
    static let recipientModeUsesNormalWorkspace = false
    static let previewWrites = false
    static let establishesIdentity = false
    static let establishesDelivery = false
    static let establishesRead = false
    static let establishesLegalEffect = false
    static let establishesSecurityApproval = false
}

@MainActor
final class RecipientReviewWorkflowCoordinatorV1 {
    private let sessions: PortableExchangeSessionStoreV2
    private let canonicalReview: PortableReviewCoordinatorV1
    private let encryptedEnvelope: EncryptedPortableEnvelopeCoordinatorV1?
    let encryptionAvailability: RecipientReviewEncryptionAvailabilityV1

    init(
        sessions: PortableExchangeSessionStoreV2,
        canonicalReview: PortableReviewCoordinatorV1,
        encryptedEnvelope: EncryptedPortableEnvelopeCoordinatorV1? = nil,
        encryptionAvailability: RecipientReviewEncryptionAvailabilityV1 = .disabled
    ) throws {
        guard (encryptionAvailability == .manualPassphraseAvailable) == (encryptedEnvelope != nil) else {
            throw encryptionAvailability == .manualPassphraseAvailable
                ? RecipientReviewWorkflowFailureV1.encryptionUnavailable
                : RecipientReviewWorkflowFailureV1.encryptionDisabled
        }
        self.sessions = sessions
        self.canonicalReview = canonicalReview
        self.encryptedEnvelope = encryptedEnvelope
        self.encryptionAvailability = encryptionAvailability
    }

    func projection(
        context: RecipientReviewWorkflowContextV1
    ) async throws -> RecipientReviewWorkflowProjectionV1 {
        let records = try await sessions.sessions(in: .review)
        let record = records.first { $0.publicRequestID == context.requestPublicID.rawValue }
        if let sessionID = context.sessionID, record?.sessionID != sessionID {
            throw RecipientReviewWorkflowFailureV1.requestUnavailable
        }
        let manifest = try await sessions.exactReviewRequestBytes(
            publicRequestID: context.requestPublicID.rawValue,
            kind: .manifest
        )
        let package = try await sessions.exactReviewRequestBytes(
            publicRequestID: context.requestPublicID.rawValue,
            kind: .package
        )
        return RecipientReviewWorkflowProjectionV1(
            requestPublicID: context.requestPublicID,
            lifecycleState: record?.state,
            hasReplayableManifest: manifest != nil,
            hasReplayablePackage: package != nil,
            canCreateResponse: context.requestManifest != nil && package != nil,
            encryptionAvailability: encryptionAvailability,
            clearExchangeRequiresVisibleWarning: true,
            previewWrites: false,
            recipientModeUsesNormalWorkspace: false,
            establishesIdentity: false,
            establishesDeliveryOrRead: false
        )
    }

    func execute(
        _ command: RecipientReviewWorkflowCommandV1,
        context: RecipientReviewWorkflowContextV1
    ) async throws -> RecipientReviewWorkflowCommandOutcomeV1 {
        switch command {
        case let .replayClearRequest(kind, acknowledgement):
            return .requestReplay(try await replayClearReviewRequest(
                publicRequestID: context.requestPublicID,
                kind: kind,
                userAcknowledgedCleartextWarning: acknowledgement
            ))
        case let .createResponse(capability, responsePublicID, body):
            guard let manifest = context.requestManifest else {
                throw RecipientReviewWorkflowFailureV1.requestUnavailable
            }
            return .responseCreated(try createResponse(
                requestManifest: manifest,
                capability: capability,
                responsePublicID: responsePublicID,
                body: body
            ))
        case let .previewImport(input):
            guard input.response.requestPublicID == context.requestPublicID else {
                throw PortableReviewFailureV1.invalidValue
            }
            return .importPreview(try await previewImport(
                response: input.response,
                capability: input.capability,
                responseRecord: input.responseRecord,
                mapping: input.mapping,
                reviewID: input.reviewID,
                basisWorkspaceRevision: input.basisWorkspaceRevision,
                decision: input.decision,
                mutationID: input.mutationID
            ))
        case let .acceptAndApply(preview, mutation, expectedRevision):
            guard preview.canonicalPlan.requestPublicID == context.requestPublicID else {
                throw PortableReviewFailureV1.invalidValue
            }
            return .canonicalApplied(try await acceptAndApply(
                preview: preview,
                inspectionReviewMutation: mutation,
                expectedRevision: expectedRevision
            ))
        case let .finalizeSessionOnly(preview, receipt):
            guard preview.canonicalPlan.requestPublicID == context.requestPublicID else {
                throw PortableReviewFailureV1.invalidValue
            }
            return .sessionFinalized(try await finalizeSessionOnly(preview: preview, receipt: receipt))
        case let .recordResponseReceivedElsewhere(response):
            guard let sessionID = context.sessionID,
                  response.requestPublicID == context.requestPublicID else {
                throw PortableReviewWorkflowFailureV1.requestUnavailable
            }
            return .unverifiedHistoryRecorded(try await recordResponseReceivedElsewhere(
                sessionID: sessionID,
                response: response
            ))
        case let .recoverAcceptAndApply(mutationID):
            try await recoverAcceptAndApply(mutationID: mutationID)
            return .recovered
        case let .openEncryptedRequest(request):
            return .encryptedRequestOpened(try await openEncryptedReviewRequest(request))
        case let .sealEncryptedResponse(request):
            return .encryptedResponseSealed(try await sealEncryptedReviewResponse(request))
        case let .protectEncryptedResponse(request, response):
            return .encryptedResponseSealed(try await protectEncryptedReviewResponse(
                opening: request,
                sealing: response
            ))
        case let .readLegacyClear(source, kind, acknowledgement):
            return .legacyClearRead(try await readLegacyClear(
                source: source,
                kind: kind,
                userAcknowledgedCleartextWarning: acknowledgement
            ))
        }
    }

    func replayClearReviewRequest(
        publicRequestID: ReviewRequestPublicIDV1,
        kind: PortableExchangeReviewRequestByteKindV2,
        userAcknowledgedCleartextWarning: Bool
    ) async throws -> RecipientReviewRequestReplayV1 {
        guard userAcknowledgedCleartextWarning else {
            throw RecipientReviewWorkflowFailureV1.cleartextWarningRequired
        }
        guard let request = try await sessions.exactReviewRequestBytes(
            publicRequestID: publicRequestID.rawValue,
            kind: kind
        ) else { throw RecipientReviewWorkflowFailureV1.requestUnavailable }
        return RecipientReviewRequestReplayV1(
            request: request,
            protection: .legacyClearWithExplicitWarning,
            isOffline: true,
            entitlementRequired: false,
            isIsolatedFromNormalWorkspaces: true
        )
    }

    /// Creates the released C48 response and proof without retaining the
    /// bearer capability. The response body digest is over canonical C48 JSON.
    func createResponse(
        requestManifest: ReviewRequestManifestV1,
        capability: BearerResponseCapabilityV1,
        responsePublicID: String,
        body: ReviewResponseBodyV1
    ) throws -> ReviewResponseEnvelopeV1 {
        try requestManifest.validate()
        try body.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let bodyDigest = Data(SHA256.hash(data: try encoder.encode(body)))
        let proof = try ReviewCapabilityProofCodecV1.makeProof(
            capability: capability,
            input: requestManifest.proofInput(canonicalResponseBodyDigest: bodyDigest)
        )
        return try ReviewResponseEnvelopeV1(
            responsePublicID: responsePublicID,
            requestPublicID: requestManifest.requestPublicID,
            body: body,
            proof: proof,
            canonicalBodyDigest: bodyDigest
        )
    }

    /// Exact proof verification and C14 planning are both read-only here.
    func previewImport(
        response: ReviewResponseEnvelopeV1,
        capability: BearerResponseCapabilityV1,
        responseRecord: ExternalReviewResponseRecordV1,
        mapping: ReviewRequestC14SubjectItemMappingV1,
        reviewID: UUID,
        basisWorkspaceRevision: UInt64,
        decision: ExternalReviewImportDecisionV1,
        mutationID: MutationIDV1
    ) async throws -> RecipientReviewImportPreviewV1 {
        let sessionPreview = try await sessions.previewImport(response, capability: capability)
        guard responseRecord.requestManifest.requestPublicID == response.requestPublicID,
              responseRecord.canonicalResponse == (try CanonicalReviewResponseBytesV1(response: response)),
              responseRecord.proofAssessment == sessionPreview.proofAssessment else {
            throw PortableReviewFailureV1.invalidValue
        }
        let plan = try canonicalReview.preview(
            responseRecord: responseRecord,
            mapping: mapping,
            reviewID: reviewID,
            basisWorkspaceRevision: basisWorkspaceRevision,
            disposition: sessionPreview.disposition,
            decision: decision,
            mutationID: mutationID
        )
        return RecipientReviewImportPreviewV1(
            sessionPreview: sessionPreview,
            canonicalPlan: plan,
            isZeroWrite: true,
            requiresExplicitDecision: true
        )
    }

    func acceptAndApply(
        preview: RecipientReviewImportPreviewV1,
        inspectionReviewMutation: InspectionReviewMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1
    ) async throws -> PortableReviewMutationReceiptV1 {
        guard preview.requiresExplicitDecision,
              preview.canonicalPlan.decision == .acceptAndApply,
              preview.canonicalPlan.disposition == .exactPendingDecision,
              preview.canonicalPlan.basisWorkspaceRevision == expectedRevision.workspaceRevision else {
            throw RecipientReviewWorkflowFailureV1.previewDecisionMismatch
        }
        return try await canonicalReview.acceptAndApply(
            plan: preview.canonicalPlan,
            inspectionReviewMutation: inspectionReviewMutation,
            expectedRevision: expectedRevision
        )
    }

    func finalizeSessionOnly(
        preview: RecipientReviewImportPreviewV1,
        receipt: ExternalReviewImportReceiptV1
    ) async throws -> ExternalReviewImportReceiptV1 {
        guard preview.canonicalPlan.decision != .acceptAndApply else {
            throw RecipientReviewWorkflowFailureV1.previewDecisionMismatch
        }
        return try await canonicalReview.finalizeSessionOnly(
            plan: preview.canonicalPlan,
            receipt: receipt
        )
    }

    func recordResponseReceivedElsewhere(
        sessionID: UUID,
        response: OriginRecordedReviewResponseV1
    ) async throws -> RecipientReviewHistoryReceiptV1 {
        guard let existing = try await sessions.session(id: sessionID),
              existing.namespace == .review,
              existing.publicRequestID == response.requestPublicID.rawValue else {
            throw RecipientReviewWorkflowFailureV1.requestUnavailable
        }
        let record = try await sessions.recordOriginResponse(sessionID: sessionID, response: response)
        return RecipientReviewHistoryReceiptV1(
            sessionID: record.sessionID,
            state: record.state,
            proofValidity: .unavailable,
            isVerifiedResponse: false,
            appliedToCanonicalWorkspace: false
        )
    }

    func recoverAcceptAndApply(mutationID: MutationIDV1) async throws {
        try await canonicalReview.recoverAcceptAndApply(mutationID: mutationID)
    }

    func openEncryptedReviewRequest(
        _ request: EncryptedPortableEnvelopeOpenRequestV1
    ) async throws -> EncryptedPortableEnvelopeOpenOutcomeV1 {
        defer { request.passphrase.clear() }
        let encryption = try requireEncryption()
        try validateEncryptedReviewRequest(request)
        return try await encryption.open(request)
    }

    func sealEncryptedReviewResponse(
        _ request: EncryptedPortableEnvelopeSealRequestV1
    ) async throws -> EncryptedPortableEnvelopeSealOutcomeV1 {
        defer { request.passphrase.clear() }
        let encryption = try requireEncryption()
        guard request.innerKind == .reviewResponse,
              request.reviewProtectionMode == .passphraseEncryptedV1 else {
            throw RecipientReviewWorkflowFailureV1.unsupportedExchangeKind
        }
        return try await encryption.seal(request)
    }

    func protectEncryptedReviewResponse(
        opening request: EncryptedPortableEnvelopeOpenRequestV1,
        sealing response: EncryptedPortableEnvelopeSealRequestV1
    ) async throws -> EncryptedPortableEnvelopeSealOutcomeV1 {
        defer { Self.clearOnce([request.passphrase, response.passphrase]) }
        let encryption = try requireEncryption()
        try validateEncryptedReviewRequest(request)
        guard response.innerKind == .reviewResponse,
              response.reviewProtectionMode == .passphraseEncryptedV1 else {
            throw RecipientReviewWorkflowFailureV1.unsupportedExchangeKind
        }
        return try await encryption.protectReviewResponse(request: request, response: response)
    }

    func readLegacyClear(
        source: any EncryptedEnvelopeBoundedSeekableSourceV1,
        kind: EncryptedPortableEnvelopeInnerKindV1,
        userAcknowledgedCleartextWarning: Bool
    ) async throws -> RecipientReviewExchangeProtectionV1 {
        guard userAcknowledgedCleartextWarning else {
            throw RecipientReviewWorkflowFailureV1.cleartextWarningRequired
        }
        guard kind == .reviewRequest || kind == .reviewResponse else {
            throw RecipientReviewWorkflowFailureV1.unsupportedExchangeKind
        }
        let encryption = try requireEncryption()
        try await encryption.readLegacyClear(
            source: source,
            kind: kind,
            version: .released(for: kind),
            protection: .clearWithExplicitWarning
        )
        return .legacyClearWithExplicitWarning
    }

    private func requireEncryption() throws -> EncryptedPortableEnvelopeCoordinatorV1 {
        guard encryptionAvailability != .disabled else {
            throw RecipientReviewWorkflowFailureV1.encryptionDisabled
        }
        guard encryptionAvailability == .manualPassphraseAvailable,
              let encryptedEnvelope else {
            throw RecipientReviewWorkflowFailureV1.encryptionUnavailable
        }
        return encryptedEnvelope
    }

    private func validateEncryptedReviewRequest(
        _ request: EncryptedPortableEnvelopeOpenRequestV1
    ) throws {
        let header: EncryptedPortableEnvelopePublicHeaderV1
        do {
            let bytes = try request.source.readExactly(
                atOffset: 0,
                byteCount: EncryptedPortableEnvelopeProtocolReleaseV1.headerByteCount
            )
            header = try EncryptedPortableEnvelopeBinaryCodecV1.decodePublicHeader(bytes)
        } catch {
            throw EncryptedPortableEnvelopeExternalFailureV1.wrongPassphraseOrDamagedEnvelope
        }
        guard header.innerKind == .reviewRequest,
              header.reviewProtectionMode == .passphraseEncryptedV1 else {
            throw RecipientReviewWorkflowFailureV1.unsupportedExchangeKind
        }
    }

    private static func clearOnce(_ secrets: [EphemeralPassphraseV1]) {
        var owners = Set<ObjectIdentifier>()
        for secret in secrets where owners.insert(ObjectIdentifier(secret)).inserted {
            secret.clear()
        }
    }
}

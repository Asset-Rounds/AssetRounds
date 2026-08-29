import Foundation
import CryptoKit

enum ScheduleContentIntegrityBoundaryV1 { static let occurrenceDigestUsesCanonicalDomainCodec = true }

enum AssetLocatorIntegrityBoundaryV1 {
    static func validateCanonicalDigest(_ digest: String) throws {
        guard KernelCanonicalHashV1.validSHA256(digest) else {
            throw AssetLocatorFailureV1.invalidDigest
        }
    }
}

enum ContentIntegrityFailureV1: Error, Equatable, Sendable {
    case wrongWorkspace
    case missingContent
    case staleLocator
    case digestMismatch
    case byteLengthMismatch
    case mediaTypeMismatch
    case immutableOriginal
    case protectedDataUnavailable
    case permissionDenied
    case cancelled
    case insufficientStorage
    case partialEffect
}

/// The one bridge from C36's verified, noncanonical draft bytes into the
/// existing C05 immutable-content writer.  This request carries metadata only;
/// the bytes are supplied separately and are never assigned an EvidenceID.
struct DraftImmutableContentWriteRequestV1: Equatable, Hashable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let contentID: String
    let digest: ContentDigestV1
    let byteLength: Int64
    let mediaType: String
    let mutationID: MutationIDV1
    let createdAt: String

    init(
        workspaceID: WorkspaceID,
        contentID: String,
        digest: ContentDigestV1,
        byteLength: Int64,
        mediaType: String,
        mutationID: MutationIDV1,
        createdAt: String
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.contentID = contentID
        self.digest = digest
        self.byteLength = byteLength
        self.mediaType = mediaType
        self.mutationID = mutationID
        self.createdAt = createdAt
        try validate()
    }

    /// The content namespace is inside the C05 generation root.  It is a
    /// content-ID path, not an EvidenceID path, and is therefore safe for
    /// audio/video/file attachments as well as JPEGs.
    var relativePath: String {
        "content/\(workspaceID.rawValue.uuidString.lowercased())/\(contentID)/original.bin"
    }

    /// Locators are scoped by WorkspaceID, so the content ID is sufficient for
    /// a stable locator identity without manufacturing an EvidenceID.
    var locatorID: String { "c05-\(contentID)" }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              workspaceID.rawValue != Self.zero,
              ContentContractValidationV1.validID(workspaceString),
              validPathComponent(contentID),
              ContentContractValidationV1.validID(locatorID),
              digest.algorithm == .sha256,
              byteLength >= 0,
              ContentContractValidationV1.validMediaType(mediaType),
              mutationID.rawValue != Self.zero,
              FindingContractValidationV1.validInstant(createdAt) else {
            throw DraftImmutableContentWriterFailureV1.invalidRequest
        }
    }

    private var workspaceString: String {
        workspaceID.rawValue.uuidString.lowercased()
    }

    private func validPathComponent(_ value: String) -> Bool {
        ContentContractValidationV1.validID(value)
            && value != "." && value != ".."
    }

    private static let zero = UUID(uuid: (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ))
}

enum DraftImmutableContentWriterFailureV1: Error, Equatable, Sendable {
    case invalidRequest
    case wrongWorkspace
    case digestMismatch
    case byteLengthMismatch
    case mediaTypeMismatch
    case pathMismatch
    case immutableConflict
}

/// Result returned only after C05 has durably written and read back the exact
/// immutable bytes.  The result is the metadata source for C36's reservation.
struct DraftImmutableContentWriteReceiptV1: Equatable, Hashable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let contentID: String
    let locatorID: String
    let relativePath: String
    let digest: ContentDigestV1
    let byteLength: Int64
    let mediaType: String
    let byteRole: ContentByteRoleV1
    let createdAt: String
    let mutationID: MutationIDV1
    let reusedExistingBytes: Bool

    init(
        request: DraftImmutableContentWriteRequestV1,
        relativePath: String,
        reusedExistingBytes: Bool
    ) throws {
        try request.validate()
        guard relativePath == request.relativePath else {
            throw DraftImmutableContentWriterFailureV1.pathMismatch
        }
        schemaVersion = Self.schemaVersion
        workspaceID = request.workspaceID
        contentID = request.contentID
        locatorID = request.locatorID
        self.relativePath = relativePath
        digest = request.digest
        byteLength = request.byteLength
        mediaType = request.mediaType
        byteRole = .immutableOriginal
        createdAt = request.createdAt
        mutationID = request.mutationID
        self.reusedExistingBytes = reusedExistingBytes
    }

    func validate(
        request: DraftImmutableContentWriteRequestV1,
        bytes: Data
    ) throws {
        try request.validate()
        guard schemaVersion == Self.schemaVersion,
              workspaceID == request.workspaceID,
              contentID == request.contentID,
              locatorID == request.locatorID,
              relativePath == request.relativePath,
              digest == request.digest,
              byteLength == request.byteLength,
              mediaType == request.mediaType,
              byteRole == .immutableOriginal,
              createdAt == request.createdAt,
              mutationID == request.mutationID else {
            throw DraftImmutableContentWriterFailureV1.pathMismatch
        }
        guard Int64(bytes.count) == request.byteLength else {
            throw DraftImmutableContentWriterFailureV1.byteLengthMismatch
        }
        let observed = try ContentIntegrityV1.observe(
            workspaceID: request.workspaceID.rawValue.uuidString.lowercased(),
            contentID: request.contentID,
            data: bytes,
            mediaType: request.mediaType,
            algorithms: ContentDigestAlgorithmV1.allCases
                .filter { $0 == .sha256 || $0 == request.digest.algorithm }
        )
        guard observed.digests.digest(for: request.digest.algorithm) == request.digest else {
            throw DraftImmutableContentWriterFailureV1.digestMismatch
        }
    }
}

/// C05 remains the sole immutable byte writer/root.  C36 may only submit a
/// complete, already-verified item through this reservation-aware seam.
protocol DraftImmutableContentWriterV1: Sendable {
    func persistImmutableOriginal(
        bytes: Data,
        request: DraftImmutableContentWriteRequestV1
    ) async throws -> DraftImmutableContentWriteReceiptV1
}

/// C20 reuses the canonical C05 byte writer under a distinct derivative
/// content ID. The returned C05 receipt proves durable read-back; it does not
/// claim the later SwiftData transaction was cross-store atomic.
struct PrivacyDerivativeByteWriteReceiptV1: Equatable, Sendable {
    let contentReceipt: DraftImmutableContentWriteReceiptV1
    let derivativeReference: ContentReferenceV1

    func validate(bytes: Data, mutationID: MutationIDV1) throws {
        guard derivativeReference.byteRole == .derivative,
              contentReceipt.contentID == derivativeReference.contentID,
              contentReceipt.mutationID == mutationID,
              contentReceipt.digest == derivativeReference.digests.digest(for: .sha256),
              contentReceipt.byteLength == derivativeReference.byteLength,
              contentReceipt.mediaType == derivativeReference.mediaType else {
            throw ContentIntegrityFailureV1.digestMismatch
        }
        let request = try DraftImmutableContentWriteRequestV1(
            workspaceID: contentReceipt.workspaceID,
            contentID: contentReceipt.contentID,
            digest: contentReceipt.digest,
            byteLength: contentReceipt.byteLength,
            mediaType: contentReceipt.mediaType,
            mutationID: mutationID,
            createdAt: contentReceipt.createdAt
        )
        try contentReceipt.validate(request: request, bytes: bytes)
    }
}

struct ExistingContentStorePrivacyDerivativeWriterV1: Sendable {
    private let writer: any DraftImmutableContentWriterV1
    init(writer: any DraftImmutableContentWriterV1) { self.writer = writer }

    func persist(bytes: Data, reference: ContentReferenceV1, workspaceID: WorkspaceID,
                 mutationID: MutationIDV1) async throws -> PrivacyDerivativeByteWriteReceiptV1 {
        guard reference.byteRole == .derivative,
              PrivacyTransformValidationV1.workspace(workspaceID, matches: reference.workspaceID),
              let digest = reference.digests.digest(for: .sha256) else {
            throw ContentIntegrityFailureV1.immutableOriginal
        }
        let request = try DraftImmutableContentWriteRequestV1(
            workspaceID: workspaceID, contentID: reference.contentID, digest: digest,
            byteLength: reference.byteLength, mediaType: reference.mediaType,
            mutationID: mutationID, createdAt: reference.createdAt
        )
        let stored = try await writer.persistImmutableOriginal(bytes: bytes, request: request)
        let receipt = PrivacyDerivativeByteWriteReceiptV1(contentReceipt: stored, derivativeReference: reference)
        try receipt.validate(bytes: bytes, mutationID: mutationID)
        return receipt
    }
}

struct ContentObservedBytesV1: Equatable, Sendable {
    let workspaceID: String
    let contentID: String
    let byteLength: Int64
    let mediaType: String
    let digests: ContentDigestSetV1

    init(
        workspaceID: String,
        contentID: String,
        byteLength: Int64,
        mediaType: String,
        digests: ContentDigestSetV1
    ) throws {
        guard ContentContractValidationV1.validID(workspaceID),
              ContentContractValidationV1.validID(contentID),
              byteLength >= 0,
              ContentContractValidationV1.validMediaType(mediaType) else {
            throw ContentContractFailureV1.invalidValue
        }
        self.workspaceID = workspaceID
        self.contentID = contentID
        self.byteLength = byteLength
        self.mediaType = mediaType
        self.digests = digests
    }
}

struct ContentIntegrityReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let receiptID: String
    let workspaceID: String
    let contentID: String
    let locatorID: String
    let locatorRevision: Int
    let verifiedDigest: ContentDigestV1
    let verifiedByteLength: Int64
    let verifiedMediaType: String

    init(
        receiptID: String,
        reference: ContentReferenceV1,
        locator: ContentLocatorV1,
        observed: ContentObservedBytesV1,
        verifiedDigest: ContentDigestV1
    ) throws {
        guard ContentContractValidationV1.validID(receiptID) else {
            throw ContentContractFailureV1.invalidValue
        }
        try ContentIntegrityV1.verify(reference: reference, locator: locator, observed: observed)
        guard reference.digests.digest(for: verifiedDigest.algorithm) == verifiedDigest else {
            throw ContentIntegrityFailureV1.digestMismatch
        }
        schemaVersion = Self.schemaVersion
        self.receiptID = receiptID
        workspaceID = reference.workspaceID
        contentID = reference.contentID
        locatorID = locator.locatorID
        locatorRevision = locator.locatorRevision
        self.verifiedDigest = verifiedDigest
        verifiedByteLength = reference.byteLength
        verifiedMediaType = reference.mediaType
    }

    func validate(
        reference: ContentReferenceV1,
        locator: ContentLocatorV1,
        observed: ContentObservedBytesV1
    ) throws {
        try ContentIntegrityV1.verify(reference: reference, locator: locator, observed: observed)
        guard workspaceID == reference.workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
        guard contentID == reference.contentID else { throw ContentContractFailureV1.missingContent }
        guard locatorID == locator.locatorID,
              locatorRevision == locator.locatorRevision else {
            throw ContentContractFailureV1.staleReference
        }
        guard reference.digests.digest(for: verifiedDigest.algorithm) == verifiedDigest else {
            throw ContentContractFailureV1.digestMismatch
        }
        guard verifiedByteLength == observed.byteLength else { throw ContentContractFailureV1.byteLengthMismatch }
        guard verifiedMediaType == observed.mediaType else { throw ContentContractFailureV1.mediaTypeMismatch }
    }
}

enum ContentIntegrityV1 {
    static func observe(
        workspaceID: String,
        contentID: String,
        data: Data,
        mediaType: String,
        algorithms: [ContentDigestAlgorithmV1] = [.sha256]
    ) throws -> ContentObservedBytesV1 {
        let digests = try algorithms.map { algorithm -> ContentDigestV1 in
            let hexadecimalValue: String
            switch algorithm {
            case .sha256:
                hexadecimalValue = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            case .sha512:
                hexadecimalValue = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }
            return try ContentDigestV1(algorithm: algorithm, hexadecimalValue: hexadecimalValue)
        }
        return try ContentObservedBytesV1(
            workspaceID: workspaceID,
            contentID: contentID,
            byteLength: Int64(data.count),
            mediaType: mediaType,
            digests: ContentDigestSetV1(digests)
        )
    }

    static func verify(
        reference: ContentReferenceV1,
        locator: ContentLocatorV1,
        observed: ContentObservedBytesV1
    ) throws {
        guard observed.workspaceID == reference.workspaceID,
              locator.workspaceID == reference.workspaceID else {
            throw ContentIntegrityFailureV1.wrongWorkspace
        }
        guard observed.contentID == reference.contentID,
              locator.contentID == reference.contentID else {
            throw ContentIntegrityFailureV1.missingContent
        }
        guard observed.byteLength == reference.byteLength,
              locator.expectedByteLength == reference.byteLength else {
            throw ContentIntegrityFailureV1.byteLengthMismatch
        }
        guard observed.mediaType == reference.mediaType else {
            throw ContentIntegrityFailureV1.mediaTypeMismatch
        }
        try locator.validate(against: reference)
        for digest in reference.digests.values {
            guard observed.digests.digest(for: digest.algorithm) == digest else {
                throw ContentIntegrityFailureV1.digestMismatch
            }
        }
    }

    static func verify(
        manifest: ContentManifestV1,
        references: [ContentReferenceV1],
        locators: [ContentLocatorV1],
        observed: [ContentObservedBytesV1]
    ) throws {
        try manifest.validate(references: references, locators: locators)
        let expected = Set(manifest.entries.map(\.contentID))
        guard Set(observed.map(\.contentID)) == expected,
              observed.count == expected.count else {
            throw ContentIntegrityFailureV1.missingContent
        }
        for entry in manifest.entries {
            guard let reference = references.first(where: { $0.contentID == entry.contentID }),
                  let locator = locators.first(where: { $0.contentID == entry.contentID }),
                  let bytes = observed.first(where: { $0.contentID == entry.contentID }) else {
                throw ContentIntegrityFailureV1.missingContent
            }
            try verify(reference: reference, locator: locator, observed: bytes)
        }
    }
}

extension ContentIntegrityReceiptV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, receiptID, workspaceID, contentID, locatorID, locatorRevision
        case verifiedDigest, verifiedByteLength, verifiedMediaType
    }

    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw ContentContractFailureV1.incompatibleVersion
        }
        let receiptID = try c.decode(String.self, forKey: .receiptID)
        let workspaceID = try c.decode(String.self, forKey: .workspaceID)
        let contentID = try c.decode(String.self, forKey: .contentID)
        let locatorID = try c.decode(String.self, forKey: .locatorID)
        let locatorRevision = try c.decode(Int.self, forKey: .locatorRevision)
        let digest = try c.decode(ContentDigestV1.self, forKey: .verifiedDigest)
        let byteLength = try c.decode(Int64.self, forKey: .verifiedByteLength)
        let mediaType = try c.decode(String.self, forKey: .verifiedMediaType)
        guard [receiptID, workspaceID, contentID, locatorID].allSatisfy(ContentContractValidationV1.validID),
              locatorRevision >= 0, byteLength >= 0,
              ContentContractValidationV1.validMediaType(mediaType) else {
            throw ContentContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.receiptID = receiptID
        self.workspaceID = workspaceID
        self.contentID = contentID
        self.locatorID = locatorID
        self.locatorRevision = locatorRevision
        verifiedDigest = digest
        verifiedByteLength = byteLength
        verifiedMediaType = mediaType
    }
}

// MARK: - C36 draft promotion boundary

/// A promotion receipt for a draft attachment is deliberately keyed by the
/// draft/stage/content digest tuple.  It contains no EvidenceID and therefore
/// cannot make a pre-commit attachment look like canonical evidence.
struct DraftContentPromotionReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let reservationID: UUID
    let workspaceID: WorkspaceID
    let draftID: UUID
    let stageID: UUID
    let contentDigest: ContentDigestV1
    let locator: ContentLocatorV1
    let byteLength: Int64
    let mediaType: String
    let immutableOriginal: Bool
    let createdAt: Date

    init(
        reservation: DraftContentReservationV1,
        reference: ContentReferenceV1,
        createdAt: Date
    ) throws {
        try ContentIntegrityV1.validateDraftReservation(
            reservation,
            reference: reference
        )
        guard createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ContentIntegrityFailureV1.partialEffect
        }
        schemaVersion = Self.schemaVersion
        reservationID = reservation.reservationID
        workspaceID = reservation.workspaceID
        draftID = reservation.draftID
        stageID = reservation.stageID
        contentDigest = reservation.contentDigest
        locator = reservation.locator
        byteLength = reference.byteLength
        mediaType = reference.mediaType
        immutableOriginal = reference.byteRole == .immutableOriginal
        self.createdAt = createdAt
    }

    func validate(reference: ContentReferenceV1) throws {
        guard schemaVersion == Self.schemaVersion,
              immutableOriginal,
              byteLength == reference.byteLength,
              mediaType == reference.mediaType,
              createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ContentIntegrityFailureV1.partialEffect
        }
        guard reference.workspaceID == workspaceID.rawValue.uuidString.lowercased(),
              locator.workspaceID == reference.workspaceID,
              locator.contentID == reference.contentID,
              locator.contentDigest == contentDigest,
              reference.digests.digest(for: contentDigest.algorithm) == contentDigest else {
            throw ContentIntegrityFailureV1.digestMismatch
        }
    }
}

enum DraftContentPromotionBoundaryV1 {
    static let assignsEvidenceID = false
    static let writesCanonicalBytes = true
    static let requiresImmutableContentWriter = true
    static let byteRole: ContentByteRoleV1 = .immutableOriginal

    static func validate(
        reservation: DraftContentReservationV1,
        reference: ContentReferenceV1
    ) throws {
        try ContentIntegrityV1.validateDraftReservation(
            reservation,
            reference: reference
        )
    }
}

extension ContentIntegrityV1 {
    /// Validates the metadata-only reservation made by the C36 staging
    /// adapter.  This is intentionally separate from `verify(reference:...)`
    /// because a reservation has no bytes and no EvidenceID yet.
    static func validateDraftReservation(
        _ reservation: DraftContentReservationV1,
        reference: ContentReferenceV1
    ) throws {
        try reservation.validate()
        guard reservation.workspaceID.rawValue.uuidString.lowercased() == reference.workspaceID,
              reservation.contentDigest == reference.digests.digest(
                  for: reservation.contentDigest.algorithm
              ),
              reservation.locator.workspaceID == reference.workspaceID,
              reservation.locator.contentID == reference.contentID,
              reservation.locator.contentDigest == reservation.contentDigest,
              reservation.locator.expectedByteLength == reference.byteLength,
              reference.byteRole == .immutableOriginal else {
            throw ContentIntegrityFailureV1.digestMismatch
        }
    }
}

extension ContentIntegrityV1 {
    static func verifyPrivacyDerivative(
        closure: PrivacyTransformLifecycleClosureV1,
        locator: ContentLocatorV1,
        observed: ContentObservedBytesV1
    ) throws {
        try closure.validate()
        try closure.manifest.original.validatePrivacyDerivative(closure.manifest.derivative)
        try verify(reference: closure.manifest.derivative, locator: locator, observed: observed)
        guard observed.digests.digest(for: .sha256)?.hexadecimalValue == closure.manifest.derivativeSHA256 else {
            throw ContentIntegrityFailureV1.digestMismatch
        }
    }
}

// MARK: - C24 accessible-document integrity boundary

/// Integrity checks for C24 are digest and structure checks over the
/// canonical tree/assessment.  No semantic node text, evidence bytes, or
/// private locator is copied into an integrity record.
enum AccessibleDocumentIntegrityBoundaryV1 {
    static let validatesStructureAndDigestOnly = true
    static let readsOriginalBytes = false
    static let persistsSemanticTree = false
    static let includesAssessorIdentity = false

    static func validateTree(_ tree: AccessibleDocumentSemanticTreeV1) throws {
        try AccessibleDocumentPrivacyTransformBoundaryV1
            .validateAudienceSafeProjection(tree)
    }

    static func validateAssessment(
        _ assessment: AccessibleDocumentAssessmentReceiptV1,
        for tree: AccessibleDocumentSemanticTreeV1
    ) throws {
        try AccessibleDocumentPrivacyTransformBoundaryV1
            .validateAudienceSafeProjection(tree, assessment: assessment)
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_Content_ContentIntegrityV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_Content_ContentIntegrityV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Content_ContentIntegrityV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Content/ContentIntegrityV1.swift", role: .content)
}

enum C31LightingContentIntegrityBoundaryV1 {
    static let projectionRequiresCanonicalDigest = true
    static let projectionDoesNotRecalculateMeasurementOrSolarFacts = true
    static let unsupportedSafetyAndComplianceClaimsRejected = true

    static func validatesProjectionDigest(_ digest: String) -> Bool {
        MutationEnvelopeV1.isSHA256(digest)
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Content_ContentIntegrityV1 {
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

// MARK: - C33 temporal evidence integrity

enum TemporalEvidenceContentIntegrityV1 {
    static func verifyOriginal(
        clip: TemporalEvidenceClipV1,
        observed: ContentObservedBytesV1
    ) throws {
        try clip.validateIntrinsic()
        try ContentIntegrityV1.verify(
            reference: clip.original,
            locator: clip.locator,
            observed: observed
        )
    }

    static func verifyDerivative(
        _ derivative: TemporalEvidenceDerivativeV1,
        clip: TemporalEvidenceClipV1,
        observed: ContentObservedBytesV1
    ) throws {
        try TemporalEvidenceProvenanceBoundaryV1.validate(
            clip: clip,
            derivative: derivative
        )
        try ContentIntegrityV1.verify(
            reference: derivative.content,
            locator: derivative.locator,
            observed: observed
        )
    }
}

/// C45 every projected artifact is rehashed before manifest adoption.
enum C45AssetLabelBoundary_ContentIntegrityV1 {
    static func validate(_ plan: AssetLabelGenerationPlanV1) throws { try plan.validate() }
    static let requiresDigestReadback = true
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Content_ContentIntegrityV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

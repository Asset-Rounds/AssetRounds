import Foundation

enum ScheduleLocalContentStoreBoundaryV1 { static let scheduleRowsBelongInByteStore = false }

enum AssetLocatorLocalContentStoreBoundaryV1 {
    static let locatorRowsBelongInContentStore = false
    static let resolverPerformsRuntimeFetch = false
}

enum LocalContentStoreAvailabilityV1: Equatable, Sendable {
    case available(remainingByteCapacity: Int64)
    case protectedDataUnavailable
    case permissionDenied
    case cancelled
}

extension LocalContentStoreV1 {
    func fieldReferenceContent(for release: FieldReferenceReleaseV1) throws -> ([ContentReferenceV1], [ContentLocatorV1]) {
        try release.validate()
        guard workspaceID == release.manifest.workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
        let ids = Set(release.manifest.entries.map(\.contentID))
        let selected = entries.values.filter { ids.contains($0.reference.contentID) }
        let references = selected.map(\.reference).sorted { $0.contentID < $1.contentID }
        let locators = selected.map(\.locator).sorted { $0.contentID < $1.contentID }
        try release.validateContent(references: references, locators: locators)
        return (references, locators)
    }
}

struct LocalContentStoreEntryV1: Equatable, Sendable {
    let reference: ContentReferenceV1
    let locator: ContentLocatorV1
    let observed: ContentObservedBytesV1
}

struct LocalContentStoreV1: Sendable {
    let workspaceID: String
    private(set) var entries: [String: LocalContentStoreEntryV1]

    init(workspaceID: String) throws {
        guard ContentContractValidationV1.validID(workspaceID) else {
            throw ContentContractFailureV1.invalidValue
        }
        self.workspaceID = workspaceID
        entries = [:]
    }

    mutating func store(
        reference: ContentReferenceV1,
        locator: ContentLocatorV1,
        observed: ContentObservedBytesV1,
        availability: LocalContentStoreAvailabilityV1
    ) throws {
        try requireAvailable(availability, byteLength: reference.byteLength)
        guard reference.workspaceID == workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
        try ContentIntegrityV1.verify(reference: reference, locator: locator, observed: observed)
        if let current = entries[reference.contentID] {
            try current.reference.validateImmutableIdentity(against: reference)
            guard current.observed == observed else { throw ContentContractFailureV1.immutableOriginal }
            guard locator.locatorRevision == current.locator.locatorRevision,
                  locator == current.locator else { throw ContentContractFailureV1.staleReference }
            return
        }
        guard !entries.values.contains(where: { $0.locator.locatorID == locator.locatorID }) else {
            throw ContentContractFailureV1.duplicateIdentity
        }
        entries[reference.contentID] = LocalContentStoreEntryV1(
            reference: reference,
            locator: locator,
            observed: observed
        )
    }

    mutating func replaceLocator(
        contentID: String,
        expectedLocatorRevision: Int,
        replacement: ContentLocatorV1
    ) throws {
        guard let current = entries[contentID] else { throw ContentContractFailureV1.missingContent }
        guard current.reference.workspaceID == workspaceID,
              replacement.workspaceID == workspaceID else {
            throw ContentContractFailureV1.wrongWorkspace
        }
        guard replacement.contentID == contentID else { throw ContentContractFailureV1.missingContent }
        guard !entries.contains(where: { key, entry in
            key != contentID && entry.locator.locatorID == replacement.locatorID
        }) else { throw ContentContractFailureV1.duplicateIdentity }
        guard current.locator.locatorRevision == expectedLocatorRevision,
              replacement.locatorRevision == expectedLocatorRevision + 1 else {
            throw ContentContractFailureV1.staleReference
        }
        try replacement.validate(against: current.reference)
        entries[contentID] = LocalContentStoreEntryV1(
            reference: current.reference,
            locator: replacement,
            observed: current.observed
        )
    }

    func resolve(_ locator: ContentLocatorV1) throws -> ContentReferenceV1 {
        guard locator.workspaceID == workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
        guard let current = entries[locator.contentID] else { throw ContentContractFailureV1.missingContent }
        guard current.locator == locator else { throw ContentContractFailureV1.staleReference }
        try locator.validate(against: current.reference)
        return current.reference
    }

    mutating func deleteRegenerableDerivative(
        contentID: String,
        provenance: ContentDerivativeProvenanceV1
    ) throws {
        guard let current = entries[contentID] else { throw ContentContractFailureV1.missingContent }
        guard current.reference.workspaceID == workspaceID,
              provenance.workspaceID == workspaceID else {
            throw ContentContractFailureV1.wrongWorkspace
        }
        guard current.reference.byteRole == .derivative,
              provenance.derivativeContentID == contentID,
              current.reference.digests.digest(for: provenance.derivativeDigest.algorithm) == provenance.derivativeDigest else {
            throw ContentContractFailureV1.immutableOriginal
        }
        entries.removeValue(forKey: contentID)
    }

    mutating func storePrivacyDerivative(
        closure: PrivacyTransformLifecycleClosureV1,
        locator: ContentLocatorV1,
        observed: ContentObservedBytesV1,
        availability: LocalContentStoreAvailabilityV1
    ) throws {
        try closure.validate()
        guard entries[closure.manifest.original.contentID]?.reference == closure.manifest.original else {
            throw ContentContractFailureV1.immutableOriginal
        }
        try store(reference: closure.manifest.derivative, locator: locator, observed: observed, availability: availability)
    }

    func immutableOriginals() -> [ContentReferenceV1] {
        entries.values.map(\.reference)
            .filter { $0.byteRole == .immutableOriginal }
            .sorted { $0.contentID < $1.contentID }
    }

    private func requireAvailable(
        _ availability: LocalContentStoreAvailabilityV1,
        byteLength: Int64
    ) throws {
        switch availability {
        case .available(let remainingByteCapacity):
            guard remainingByteCapacity >= byteLength else {
                throw ContentIntegrityFailureV1.insufficientStorage
            }
        case .protectedDataUnavailable:
            throw ContentIntegrityFailureV1.protectedDataUnavailable
        case .permissionDenied:
            throw ContentIntegrityFailureV1.permissionDenied
        case .cancelled:
            throw ContentIntegrityFailureV1.cancelled
        }
    }
}

// ContentReferenceV1 intentionally contains no external storage coordinates or
// delivery lifecycle state. Only LocalContentStoreV1 resolves the opaque
// ContentLocatorV1, which cannot change canonical identity.

// MARK: - C36 draft reservation boundary

/// C36 uses the local content store only after a draft has produced a valid
/// immutable reservation.  This value makes that boundary explicit for
/// callers that need to carry the result across an async job without carrying
/// bytes or an EvidenceID.
struct DraftLocalContentReservationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let reservation: DraftContentReservationV1
    let byteRole: ContentByteRoleV1
    let backupIncluded: Bool
    let exportIncluded: Bool

    init(reservation: DraftContentReservationV1) throws {
        try reservation.validate()
        schemaVersion = Self.schemaVersion
        self.reservation = reservation
        byteRole = .immutableOriginal
        // The reservation is metadata-only until the canonical commit binds
        // it.  In particular, this object cannot turn staging bytes into a
        // portable export or a user backup member.
        backupIncluded = false
        exportIncluded = false
    }

    func validate(workspaceID: WorkspaceID, draftID: UUID) throws {
        guard schemaVersion == Self.schemaVersion,
              byteRole == .immutableOriginal,
              backupIncluded == false,
              exportIncluded == false,
              reservation.workspaceID == workspaceID,
              reservation.draftID == draftID else {
            throw ContentContractFailureV1.invalidValue
        }
        try reservation.validate()
    }
}

enum LocalContentStoreDraftBoundaryV1 {
    static let requiresCanonicalCommit = true
    static let carriesEvidenceID = false
    static let storesStagingBytes = false

    static func validate(
        _ reservation: DraftContentReservationV1,
        workspaceID: WorkspaceID,
        draftID: UUID
    ) throws {
        try DraftLocalContentReservationV1(reservation: reservation)
            .validate(workspaceID: workspaceID, draftID: draftID)
    }
}

// MARK: - C24 accessible-document content consumer

extension LocalContentStoreV1 {
    /// Validates the report companion at the content boundary without
    /// resolving bytes or exposing a locator.  Semantic-tree data remains a
    /// disposable derivative of the canonical report snapshot.
    func validateAccessibleDocumentProjection(
        _ tree: AccessibleDocumentSemanticTreeV1
    ) throws {
        guard tree.workspaceID.rawValue.uuidString.lowercased() == workspaceID else {
            throw ContentContractFailureV1.wrongWorkspace
        }
        try AccessibleDocumentPrivacyTransformBoundaryV1
            .validateAudienceSafeProjection(tree)
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_Content_LocalContentStoreContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_Content_LocalContentStoreContractsV1_swift {
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
enum C30ConsumerBoundaryV1_Infrastructure_Content_LocalContentStoreContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Content/LocalContentStoreContractsV1.swift", role: .content)
}

enum C31LightingLocalContentStoreBoundaryV1 {
    static let canonicalLightingProjectionStoresMetadataOnly = true
    static let originalAndDerivedBytesUseExistingContentStore = true
    static let searchAndReportNeverReadPrivateLocators = true

    static func permitsProjectionRead() -> Bool {
        canonicalLightingProjectionStoresMetadataOnly
            && originalAndDerivedBytesUseExistingContentStore
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Content_LocalContentStoreContractsV1 {
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

// MARK: - C33 incremental temporal-media admission

/// Admission is incremental and uses the current store capacity at every
/// boundary. This is not a byte writer and cannot make partial scratch bytes
/// canonical.
enum TemporalEvidenceLocalContentAdmissionV1 {
    static let secondByteStoreAllowed = false

    static func validate(
        facts: TemporalEvidenceMediaFactsV1,
        profile: TemporalEvidenceLimitProfileV1,
        availability: LocalContentStoreAvailabilityV1
    ) throws {
        try facts.validate(against: profile.limit(for: facts.kind))
        switch availability {
        case .available(let remainingByteCapacity):
            guard facts.byteCount <= UInt64(Int64.max),
                  profile.minimumFreeByteCount <= UInt64(Int64.max) else {
                throw ContentContractFailureV1.limitExceeded
            }
            let requiredBytes = Int64(facts.byteCount)
            let reserveBytes = Int64(profile.minimumFreeByteCount)
            guard remainingByteCapacity >= requiredBytes,
                  remainingByteCapacity - requiredBytes >= reserveBytes else {
                throw ContentContractFailureV1.limitExceeded
            }
        case .protectedDataUnavailable, .permissionDenied, .cancelled:
            throw ContentContractFailureV1.limitExceeded
        }
    }
}


enum TemporalEvidenceIncrementalBudgetStateV1: Equatable, Sendable {
    case recording
    case stopped(TemporalEvidenceStopReasonV1)
    case completed

    var isTerminal: Bool {
        switch self { case .recording: false; case .stopped, .completed: true }
    }
}

/// Immutable receipt for one incremental boundary evaluation. A stopped or
/// completed receipt cannot resume, and simultaneous bounds use this fixed
/// first-reason order: explicit terminal state, codec/resolution, counts,
/// storage, duration, then bytes.
struct TemporalEvidenceIncrementalBudgetReceiptV1: Equatable, Sendable {
    let profileSHA256: String
    let kind: TemporalEvidenceMediaKindV1
    let durationMilliseconds: UInt64
    let byteCount: UInt64
    let availableByteCount: UInt64
    let clipsForRequirement: Int
    let clipsForSession: Int
    let codec: TemporalEvidenceCodecV1
    let containerMediaType: String
    let pixelWidth: Int?
    let pixelHeight: Int?
    let state: TemporalEvidenceIncrementalBudgetStateV1
    let canonicalReceipt: TemporalEvidenceIncrementalAdmissionReceiptV1

    func validate(profile: TemporalEvidenceLimitProfileV1) throws {
        try profile.validate(); let limit = profile.limit(for: kind)
        guard profileSHA256 == profile.profileSHA256,
              clipsForRequirement >= 0, clipsForSession >= clipsForRequirement,
              containerMediaType == codec.mediaType,
              canonicalReceipt.profileSHA256 == profileSHA256,
              canonicalReceipt.kind == kind, canonicalReceipt.codec == codec,
              canonicalReceipt.observedDurationMilliseconds
                == min(durationMilliseconds, limit.maximumDurationMilliseconds),
              canonicalReceipt.observedByteCount
                == min(byteCount, limit.maximumByteCount),
              canonicalReceipt.captureCompleted == {
                switch state {
                case .completed, .stopped(.durationBound), .stopped(.byteBound): true
                default: false
                }
              }(),
              state.isTerminal || (durationMilliseconds < limit.maximumDurationMilliseconds
                && byteCount < limit.maximumByteCount) else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
        try canonicalReceipt.validate(profile: profile)
    }

    func validateCompleted(facts: TemporalEvidenceMediaFactsV1,
                           profile: TemporalEvidenceLimitProfileV1) throws {
        try validate(profile: profile); try facts.validate(against: profile.limit(for: facts.kind))
        let isAcceptedTerminal: Bool
        switch state {
        case .completed, .stopped(.durationBound), .stopped(.byteBound):
            isAcceptedTerminal = true
        default: isAcceptedTerminal = false
        }
        guard isAcceptedTerminal, kind == facts.kind,
              durationMilliseconds == facts.durationMilliseconds,
              byteCount == facts.byteCount, codec == facts.codec,
              pixelWidth == facts.pixelWidth, pixelHeight == facts.pixelHeight else {
            throw TemporalEvidenceContractFailureV1.invalidTransition
        }
        try canonicalReceipt.validateTerminal(facts: facts, profile: profile)
    }
}

enum TemporalEvidenceIncrementalAdmissionEvaluatorV1 {
    static func evaluate(
        profile: TemporalEvidenceLimitProfileV1,
        kind: TemporalEvidenceMediaKindV1,
        durationMilliseconds: UInt64,
        byteCount: UInt64,
        availableByteCount: UInt64,
        clipsForRequirement: Int,
        clipsForSession: Int,
        codec: TemporalEvidenceCodecV1,
        containerMediaType: String,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        explicitStop: TemporalEvidenceStopReasonV1? = nil,
        captureCompleted: Bool = false,
        predecessor: TemporalEvidenceIncrementalBudgetReceiptV1? = nil
    ) throws -> TemporalEvidenceIncrementalBudgetReceiptV1 {
        try profile.validate(); let limit = profile.limit(for: kind)
        if let predecessor {
            try predecessor.validate(profile: profile)
            guard !predecessor.state.isTerminal,
                  predecessor.profileSHA256 == profile.profileSHA256,
                  predecessor.kind == kind,
                  durationMilliseconds >= predecessor.durationMilliseconds,
                  byteCount >= predecessor.byteCount else {
                throw TemporalEvidenceContractFailureV1.invalidTransition
            }
        }
        let supportedResolution: Bool
        switch kind {
        case .audio:
            supportedResolution = pixelWidth == nil && pixelHeight == nil
        case .video:
            if let pixelWidth, let pixelHeight,
               let maximumPixelWidth = limit.maximumPixelWidth,
               let maximumPixelHeight = limit.maximumPixelHeight {
                supportedResolution = pixelWidth > 0 && pixelHeight > 0
                    && pixelWidth <= maximumPixelWidth
                    && pixelHeight <= maximumPixelHeight
            } else { supportedResolution = false }
        }
        let unsupportedMedia = !limit.acceptedCodecs.contains(codec)
            || containerMediaType.lowercased() != codec.mediaType
            || !supportedResolution
        let reserveFits = availableByteCount >= profile.minimumFreeByteCount
            && byteCount <= availableByteCount - profile.minimumFreeByteCount
        let state: TemporalEvidenceIncrementalBudgetStateV1
        if let explicitStop { state = .stopped(explicitStop) }
        else if unsupportedMedia { state = .stopped(.codecUnavailable) }
        else if clipsForRequirement >= profile.maximumClipsPerRequirement {
            state = .stopped(.requirementCountBound)
        } else if clipsForSession >= profile.maximumClipsPerSession {
            state = .stopped(.sessionCountBound)
        } else if !reserveFits { state = .stopped(.insufficientStorage) }
        else if durationMilliseconds >= limit.maximumDurationMilliseconds {
            state = .stopped(.durationBound)
        } else if byteCount >= limit.maximumByteCount { state = .stopped(.byteBound) }
        else if captureCompleted { state = .completed }
        else { state = .recording }
        let canonical = try TemporalEvidenceIncrementalAdmissionReceiptV1(
            profile: profile, kind: kind, codec: codec,
            observedDurationMilliseconds: durationMilliseconds,
            observedByteCount: byteCount,
            sequence: (predecessor?.canonicalReceipt.sequence ?? 0) + 1,
            captureCompleted: captureCompleted
                || durationMilliseconds >= limit.maximumDurationMilliseconds
                || byteCount >= limit.maximumByteCount,
            prior: predecessor?.canonicalReceipt
        )
        let receipt = TemporalEvidenceIncrementalBudgetReceiptV1(
            profileSHA256: profile.profileSHA256, kind: kind,
            durationMilliseconds: durationMilliseconds, byteCount: byteCount,
            availableByteCount: availableByteCount,
            clipsForRequirement: clipsForRequirement, clipsForSession: clipsForSession,
            codec: codec, containerMediaType: containerMediaType.lowercased(),
            pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            state: state, canonicalReceipt: canonical
        )
        try receipt.validate(profile: profile)
        return receipt
    }
}

/// C45 label outputs reuse the one local content store and atomic adoption.
enum C45AssetLabelBoundary_LocalContentStoreContractsV1 {
    static func validate(_ plan: AssetLabelGenerationPlanV1) throws { try plan.validate() }
    static let createsSecondByteStore = false
}

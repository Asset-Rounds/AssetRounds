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

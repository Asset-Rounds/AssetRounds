import Foundation

/// The portable service-request files are cleartext, deterministic, and
/// independent of `.arenvelope`.  The shared C48 store owns backup/restore,
/// clone/fork, journal/replay, erase, and quarantine for the service namespace.
/// Their released suffixes are `arserviceinvite` and `arservicesubmission`.
/// This adapter does not add a store or a canonical writer.
enum PortableServiceRequestCodecV1 {
    static let invitationFileExtension = PortableServiceRequestProtocolReleaseV1.invitationExtension
    static let submissionFileExtension = PortableServiceRequestProtocolReleaseV1.submissionExtension

    static func encodeInvitation(
        _ invitation: PortableServiceRequestInvitationV1
    ) throws -> Data {
        try invitation.validate()
        let bytes = try ServiceRequestCanonicalCodecV1.data(invitation)
        try validatePortableBytes(bytes)
        guard try ServiceRequestCanonicalCodecV1.decode(
            PortableServiceRequestInvitationV1.self,
            from: bytes
        ) == invitation else {
            throw ServiceRequestFailureV1.nonCanonicalEncoding
        }
        return bytes
    }

    static func decodeInvitation(
        _ bytes: Data
    ) throws -> PortableServiceRequestInvitationV1 {
        try validatePortableBytes(bytes)
        let invitation = try ServiceRequestCanonicalCodecV1.decode(
            PortableServiceRequestInvitationV1.self,
            from: bytes
        )
        try invitation.validate()
        return invitation
    }

    static func encodeSubmission(
        _ submission: PortableServiceRequestSubmissionV1
    ) throws -> Data {
        try submission.validate()
        try submission.mediaManifest.validate()
        let bytes = try ServiceRequestCanonicalCodecV1.data(submission)
        try validatePortableBytes(bytes)
        guard try ServiceRequestCanonicalCodecV1.decode(
            PortableServiceRequestSubmissionV1.self,
            from: bytes
        ) == submission else {
            throw ServiceRequestFailureV1.nonCanonicalEncoding
        }
        return bytes
    }

    static func decodeSubmission(
        _ bytes: Data
    ) throws -> PortableServiceRequestSubmissionV1 {
        try validatePortableBytes(bytes)
        let submission = try ServiceRequestCanonicalCodecV1.decode(
            PortableServiceRequestSubmissionV1.self,
            from: bytes
        )
        try submission.validate()
        try submission.mediaManifest.validate()
        return submission
    }

    static func admitInvitation(
        _ bytes: Data,
        fileExtension: String = PortableServiceRequestCodecV1.invitationFileExtension,
        release: PortableServiceRequestProtocolReleaseV1? = nil
    ) throws -> PortableServiceRequestInvitationV1 {
        guard fileExtension == invitationFileExtension else {
            throw ServiceRequestFailureV1.incompatibleVersion
        }
        let invitation = try decodeInvitation(bytes)
        if let release {
            try release.validate()
            guard invitation.manifest.protocolReleaseSHA256 == release.releaseSHA256 else {
                throw ServiceRequestFailureV1.scopeMismatch
            }
        }
        return invitation
    }

    static func admitSubmission(
        _ bytes: Data,
        fileExtension: String = PortableServiceRequestCodecV1.submissionFileExtension,
        release: PortableServiceRequestProtocolReleaseV1? = nil
    ) throws -> PortableServiceRequestSubmissionV1 {
        guard fileExtension == submissionFileExtension else {
            throw ServiceRequestFailureV1.incompatibleVersion
        }
        let submission = try decodeSubmission(bytes)
        if let release {
            try release.validate()
            guard bytes.count <= release.budget.maximumSubmissionBytes else {
                throw ServiceRequestFailureV1.limitExceeded
            }
            guard submission.protocolReleaseSHA256 == release.releaseSHA256 else {
                throw ServiceRequestFailureV1.scopeMismatch
            }
        }
        return submission
    }

    static func validateMediaSanitization(
        _ manifest: ServiceRequestMediaManifestV1
    ) throws -> ServiceRequestMediaManifestV1 {
        try manifest.validate()
        guard manifest.entries.allSatisfy({ entry in
            entry.orientationBaked
                && entry.metadataStripped
                && entry.provenance == .recipientSuppliedDerivative
        }) else {
            throw ServiceRequestFailureV1.invalidValue
        }
        return manifest
    }

    static func validateEnvelopeInnerKind(_ kind: String) throws {
        guard envelopeInnerKindIsPermitted(kind) else {
            throw ServiceRequestFailureV1.incompatibleVersion
        }
    }

    static func rejectEnvelopeInnerKind(_ kind: String) throws {
        try validateEnvelopeInnerKind(kind)
    }

    static func envelopeInnerKindIsPermitted(_ kind: String) -> Bool {
        if PortableServiceRequestFormatBoundaryV1.serviceRequestEnvelopeInnerKindPermitted {
            return false
        }
        return !serviceEnvelopeKinds.contains(kind.uppercased())
    }

    /// The invitation intentionally carries the forwarding secret.  The
    /// submission and the projection bytes must not carry that secret.
    static func assertSubmissionBytesExcludeCapability(
        _ bytes: Data,
        capability: ServiceRequestSubmissionCapabilityV1
    ) throws {
        _ = try decodeSubmission(bytes)
        try assertBytesExcludeCapability(bytes, capability: capability)
    }

    static func assertSubmissionExcludesCapability(
        _ submission: PortableServiceRequestSubmissionV1,
        capability: ServiceRequestSubmissionCapabilityV1
    ) throws {
        try assertSubmissionBytesExcludeCapability(
            encodeSubmission(submission),
            capability: capability
        )
    }

    static func assertRecordBytesExcludeCapability(
        _ record: ServiceRequestRecordV1,
        capability: ServiceRequestSubmissionCapabilityV1
    ) throws {
        try record.validate()
        let bytes = try ServiceRequestCanonicalCodecV1.data(record)
        try validatePortableBytes(bytes)
        guard bytes.range(of: capability.rawBytes) == nil,
              let base64 = capability.rawBytes.base64EncodedString().data(using: .utf8),
              bytes.range(of: base64) == nil else {
            throw ServiceRequestFailureV1.invalidCapability
        }
    }

    private static let serviceEnvelopeKinds: Set<String> = [
        "SERVICE_REQUEST",
        "PORTABLE_SERVICE_REQUEST",
        "SERVICE_REQUEST_INVITATION",
        "SERVICE_REQUEST_SUBMISSION",
        "PORTABLE_SERVICE_REQUEST_INVITATION",
        "PORTABLE_SERVICE_REQUEST_SUBMISSION",
        "PORTABLE_SERVICE_REQUEST_V1",
        "AR_SERVICE_REQUEST_INVITATION_V1",
        "AR_SERVICE_REQUEST_SUBMISSION_V1",
        "AR_SERVICE_INVITATION_V1",
        "AR_SERVICE_SUBMISSION_V1",
    ]

    private static func validatePortableBytes(_ bytes: Data) throws {
        guard !bytes.isEmpty,
              bytes.count <= ServiceRequestLimitsV1.maximumPortableFileBytes else {
            throw ServiceRequestFailureV1.limitExceeded
        }
    }

    private static func assertBytesExcludeCapability(
        _ bytes: Data,
        capability: ServiceRequestSubmissionCapabilityV1
    ) throws {
        try validatePortableBytes(bytes)
        guard !containsCapabilityEncoding(capability, in: bytes) else {
            throw ServiceRequestFailureV1.invalidCapability
        }
    }

    private static func containsCapabilityEncoding(
        _ capability: ServiceRequestSubmissionCapabilityV1,
        in bytes: Data
    ) -> Bool {
        if bytes.range(of: capability.rawBytes) != nil {
            return true
        }
        guard let base64 = capability.rawBytes.base64EncodedString().data(using: .utf8) else {
            return false
        }
        return bytes.range(of: base64) != nil
    }
}

/// A nonpersistent projection of the protected exchange state.  It exposes
/// state and capability lifecycle facts, never the protected bytes.
struct ServiceRequestLifecycleProjectionV1: Equatable, Sendable {
    let invitationPublicID: ServiceRequestInvitationPublicIDV1
    let submissionPublicIDs: [ServiceRequestSubmissionPublicIDV1]
    let state: PortableExchangeSessionStateV2
    let capabilityState: PortableExchangeCapabilityStateV2
    let protectedCapabilityAvailable: Bool
    let isTerminal: Bool
    let cloneOrForkGenerationID: UUID?
    let escapedCopyAcknowledged: Bool

    init(record: PortableExchangeSessionRecordV2) throws {
        let validated = try record.validated()
        guard validated.namespace == .serviceRequest else {
            throw ServiceRequestFailureV1.scopeMismatch
        }
        invitationPublicID = try ServiceRequestInvitationPublicIDV1(
            validated.publicRequestID
        )
        submissionPublicIDs = try validated.responseIDs.map {
            try ServiceRequestSubmissionPublicIDV1($0)
        }
        state = validated.state
        capabilityState = validated.capabilityState
        protectedCapabilityAvailable = validated.protectedCapability != nil
        isTerminal = validated.state.isImmutableHistory
        cloneOrForkGenerationID = validated.cloneOrForkGenerationID
        escapedCopyAcknowledged = validated.escapedCopyAcknowledged
    }
}

/// C52's lifecycle adapter delegates every durable operation to the single
/// C48 actor.  It performs cleartext admission and typed namespace routing;
/// review-only methods remain on the review facade.
actor ServiceRequestLifecycleAdapterV1 {
    private let store: any PortableExchangeSessionStorePortV2 & PortableExchangeServiceRequestStorePortV2

    init(
        store: any PortableExchangeSessionStorePortV2 & PortableExchangeServiceRequestStorePortV2
    ) {
        self.store = store
    }

    init(
        applicationSupportURL: URL,
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource(),
        fileManager: FileManager = .default
    ) throws {
        self.store = try PortableExchangeSessionStoreV2(
            applicationSupportURL: applicationSupportURL,
            clock: clock,
            idSource: idSource,
            fileManager: fileManager
        )
    }

    nonisolated static func encodeInvitation(
        _ invitation: PortableServiceRequestInvitationV1
    ) throws -> Data {
        try PortableServiceRequestCodecV1.encodeInvitation(invitation)
    }

    nonisolated static func decodeInvitation(
        _ bytes: Data
    ) throws -> PortableServiceRequestInvitationV1 {
        try PortableServiceRequestCodecV1.decodeInvitation(bytes)
    }

    nonisolated static func encodeSubmission(
        _ submission: PortableServiceRequestSubmissionV1
    ) throws -> Data {
        try PortableServiceRequestCodecV1.encodeSubmission(submission)
    }

    nonisolated static func decodeSubmission(
        _ bytes: Data
    ) throws -> PortableServiceRequestSubmissionV1 {
        try PortableServiceRequestCodecV1.decodeSubmission(bytes)
    }

    nonisolated static func admitInvitation(
        _ bytes: Data,
        fileExtension: String = PortableServiceRequestCodecV1.invitationFileExtension,
        release: PortableServiceRequestProtocolReleaseV1? = nil
    ) throws -> PortableServiceRequestInvitationV1 {
        try PortableServiceRequestCodecV1.admitInvitation(
            bytes,
            fileExtension: fileExtension,
            release: release
        )
    }

    nonisolated static func admitSubmission(
        _ bytes: Data,
        fileExtension: String = PortableServiceRequestCodecV1.submissionFileExtension,
        release: PortableServiceRequestProtocolReleaseV1? = nil
    ) throws -> PortableServiceRequestSubmissionV1 {
        try PortableServiceRequestCodecV1.admitSubmission(
            bytes,
            fileExtension: fileExtension,
            release: release
        )
    }

    nonisolated static func validateMediaSanitization(
        _ manifest: ServiceRequestMediaManifestV1
    ) throws -> ServiceRequestMediaManifestV1 {
        try PortableServiceRequestCodecV1.validateMediaSanitization(manifest)
    }

    nonisolated static func validateEnvelopeInnerKind(_ kind: String) throws {
        try PortableServiceRequestCodecV1.validateEnvelopeInnerKind(kind)
    }

    nonisolated static func rejectEnvelopeInnerKind(_ kind: String) throws {
        try PortableServiceRequestCodecV1.rejectEnvelopeInnerKind(kind)
    }

    nonisolated static func envelopeInnerKindIsPermitted(_ kind: String) -> Bool {
        PortableServiceRequestCodecV1.envelopeInnerKindIsPermitted(kind)
    }

    nonisolated static func assertSubmissionBytesExcludeCapability(
        _ bytes: Data,
        capability: ServiceRequestSubmissionCapabilityV1
    ) throws {
        try PortableServiceRequestCodecV1.assertSubmissionBytesExcludeCapability(
            bytes,
            capability: capability
        )
    }

    nonisolated static func assertSubmissionExcludesCapability(
        _ submission: PortableServiceRequestSubmissionV1,
        capability: ServiceRequestSubmissionCapabilityV1
    ) throws {
        try PortableServiceRequestCodecV1.assertSubmissionExcludesCapability(
            submission,
            capability: capability
        )
    }

    nonisolated static func assertRecordBytesExcludeCapability(
        _ record: ServiceRequestRecordV1,
        capability: ServiceRequestSubmissionCapabilityV1
    ) throws {
        try PortableServiceRequestCodecV1.assertRecordBytesExcludeCapability(
            record,
            capability: capability
        )
    }

    nonisolated static func recoveryStateSHA256(
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) throws -> String {
        try PortableExchangeSessionStoreV2.recoveryStateSHA256(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
    }

    nonisolated static func restoreSnapshotForRecovery(
        applicationSupportURL: URL,
        snapshot: PortableExchangeBackupSnapshotV2,
        operationID: UUID,
        expectedResultGenerationID: UUID,
        cloneOrFork: Bool,
        expectedBeforeEnvelopeSHA256: String,
        fileManager: FileManager = .default
    ) throws -> PortableExchangeRestoreReceiptV2 {
        try PortableExchangeSessionStoreV2.restoreSnapshotForRecovery(
            applicationSupportURL: applicationSupportURL,
            snapshot: snapshot,
            operationID: operationID,
            expectedResultGenerationID: expectedResultGenerationID,
            cloneOrFork: cloneOrFork,
            expectedBeforeEnvelopeSHA256: expectedBeforeEnvelopeSHA256,
            fileManager: fileManager
        )
    }

    func stageInvitation(
        _ invitation: PortableServiceRequestInvitationV1,
        release: PortableServiceRequestProtocolReleaseV1,
        sessionID: UUID? = nil,
        workspaceID: UUID? = nil
    ) async throws -> PortableExchangeSessionRecordV2 {
        try PortableServiceRequestCodecV1.encodeInvitation(invitation)
        return try await store.stageServiceRequestInvitation(
            PortableExchangeServiceRequestInvitationStageInputV2(
                sessionID: sessionID,
                invitation: invitation,
                protocolRelease: release,
                workspaceID: workspaceID
            )
        )
    }

    func markInvitationExported(
        _ invitationPublicID: ServiceRequestInvitationPublicIDV1
    ) async throws -> PortableExchangeSessionRecordV2 {
        try await store.markServiceRequestInvitationExported(invitationPublicID)
    }

    func invitationManifest(
        _ invitationPublicID: ServiceRequestInvitationPublicIDV1
    ) async throws -> Data? {
        try await store.serviceRequestManifestBytes(
            invitationPublicID: invitationPublicID
        )
    }

    func submissionSource(
        invitationPublicID: ServiceRequestInvitationPublicIDV1,
        submissionPublicID: ServiceRequestSubmissionPublicIDV1
    ) async throws -> Data? {
        try await store.serviceRequestSourceBytes(
            invitationPublicID: invitationPublicID,
            submissionPublicID: submissionPublicID
        )
    }

    func serviceRequestSession(
        invitationPublicID: ServiceRequestInvitationPublicIDV1
    ) async throws -> PortableExchangeSessionRecordV2? {
        try await store.serviceRequestSession(invitationPublicID: invitationPublicID)
    }

    func previewSubmission(
        _ submission: PortableServiceRequestSubmissionV1,
        sourceBytes: Data,
        capability: ServiceRequestSubmissionCapabilityV1? = nil
    ) async throws -> PortableExchangeServiceRequestImportPreviewV2 {
        if let capability {
            try PortableServiceRequestCodecV1.assertSubmissionExcludesCapability(
                submission,
                capability: capability
            )
        }
        return try await store.previewServiceRequest(
            submission,
            sourceBytes: sourceBytes,
            capability: capability
        )
    }

    func applySubmission(
        _ submission: PortableServiceRequestSubmissionV1,
        sourceBytes: Data,
        disposition: ServiceRequestImportDispositionV1,
        capability: ServiceRequestSubmissionCapabilityV1? = nil,
        operationID: UUID = UUID()
    ) async throws -> PortableExchangeServiceRequestImportReceiptV2 {
        return try await store.applyServiceRequestImport(
            submission,
            sourceBytes: sourceBytes,
            disposition: disposition,
            capability: capability,
            operationID: operationID
        )
    }

    func prepareSubmission(
        plan: ServiceRequestImportPlanV1,
        receipt: ServiceRequestImportReceiptV1,
        submission: PortableServiceRequestSubmissionV1,
        sourceBytes: Data,
        capability: ServiceRequestSubmissionCapabilityV1? = nil
    ) async throws -> PortableExchangeServiceRequestReconciliationReceiptV2 {
        try await store.prepareServiceRequestImport(
            plan: plan,
            receipt: receipt,
            submission: submission,
            sourceBytes: sourceBytes,
            capability: capability
        )
    }

    func finalizeSubmission(
        plan: ServiceRequestImportPlanV1,
        receipt: ServiceRequestImportReceiptV1
    ) async throws -> PortableExchangeServiceRequestReconciliationReceiptV2 {
        try await store.finalizeServiceRequestImport(plan: plan, receipt: receipt)
    }

    func recoverSubmission(
        _ receipt: ServiceRequestImportReceiptV1
    ) async throws -> PortableExchangeServiceRequestReconciliationReceiptV2 {
        try await store.recoverServiceRequestImport(receipt)
    }

    func quarantineSubmission(
        _ bytes: Data,
        reason: String = ServiceRequestImportDispositionV1.keepQuarantined.rawValue
    ) async throws {
        try await store.quarantineServiceRequest(bytes, reason: reason)
    }

    func snapshotForBackup() async throws -> PortableExchangeBackupSnapshotV2 {
        try await store.snapshotForBackup()
    }

    func replaceRestore(
        with snapshot: PortableExchangeBackupSnapshotV2,
        operationID: UUID
    ) async throws -> PortableExchangeRestoreReceiptV2 {
        try await store.replaceRestore(with: snapshot, operationID: operationID)
    }

    func markClonedOrForked(
        operationID: UUID,
        resultGenerationID: UUID
    ) async throws -> PortableExchangeCloneForkReceiptV2 {
        try await store.markClonedOrForked(
            operationID: operationID,
            resultGenerationID: resultGenerationID
        )
    }

    func erase(
        operationID: UUID
    ) async throws -> PortableExchangeEraseReceiptV2 {
        try await store.erase(operationID: operationID)
    }

    func lifecycleProjection(
        for invitationPublicID: ServiceRequestInvitationPublicIDV1
    ) async throws -> ServiceRequestLifecycleProjectionV1? {
        guard let record = try await store.serviceRequestSession(
            invitationPublicID: invitationPublicID
        ) else { return nil }
        return try ServiceRequestLifecycleProjectionV1(record: record)
    }

    func lifecycleProjections() async throws -> [ServiceRequestLifecycleProjectionV1] {
        let records = try await store.sessions(in: .serviceRequest)
        return try records.map {
            try ServiceRequestLifecycleProjectionV1(record: $0)
        }
    }
}

enum C52PortableServiceRequestLifecycleBoundaryV1 {
    static let sharedStoreType: Any.Type = PortableExchangeSessionStoreV2.self
    static let serviceRequestNamespace = PortableExchangeSessionNamespaceV2.serviceRequest
    static let reviewOnlyMethodsRemainReviewOnly = true
    static let rawCapabilityIsProtectedArtifactOnly = true
    static let namespacesHaveIndependentQuotas = true
    static let cloneForkInvalidatesCapability = true
    static let backupRestoreAreEnrolled = true
    static let eraseIsEnrolled = true
    static let cleartextFilesAreReadableAndForwardable = true
    static let arenvelopeRejectsServiceKinds = true
    static let sanitizedMediaMetadataIsRequired = true
    static let duplicateProjectionIsNonpersistent = true
    static let createsSecondStore = false
    static let createsSecondWriter = false
    static let reusesC14ReviewResponseAPIs = false
}

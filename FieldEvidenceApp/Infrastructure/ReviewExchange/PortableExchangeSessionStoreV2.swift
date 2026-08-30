import Foundation
import Darwin

/// Input for the one C48 staging writer.  The capability is accepted as an
/// in-memory value only; it is never encoded into this input or into the
/// session envelope.
struct PortableExchangeSessionStageInputV2: Sendable {
    let sessionID: UUID?
    let namespace: PortableExchangeSessionNamespaceV2
    let publicRequestID: String
    let revision: Int
    let workspaceID: UUID?
    let canonicalReviewIdentity: String?
    let canonicalSubjectIdentity: String?
    let protocolReleaseDigest: Data?
    let requestManifestBytes: Data?
    let requestPackageBytes: Data?
    let capability: BearerResponseCapabilityV1?
    let state: PortableExchangeSessionStateV2

    init(
        sessionID: UUID? = nil,
        namespace: PortableExchangeSessionNamespaceV2 = .review,
        publicRequestID: String,
        revision: Int = 1,
        workspaceID: UUID? = nil,
        canonicalReviewIdentity: String? = nil,
        canonicalSubjectIdentity: String? = nil,
        protocolReleaseDigest: Data? = nil,
        requestManifestBytes: Data? = nil,
        requestPackageBytes: Data? = nil,
        capability: BearerResponseCapabilityV1? = nil,
        state: PortableExchangeSessionStateV2 = .openUnexported
    ) {
        self.sessionID = sessionID
        self.namespace = namespace
        self.publicRequestID = publicRequestID
        self.revision = revision
        self.workspaceID = workspaceID
        self.canonicalReviewIdentity = canonicalReviewIdentity
        self.canonicalSubjectIdentity = canonicalSubjectIdentity
        self.protocolReleaseDigest = protocolReleaseDigest
        self.requestManifestBytes = requestManifestBytes
        self.requestPackageBytes = requestPackageBytes
        self.capability = capability
        self.state = state
    }
}

enum C50PortableExchangeSessionStoreDelegationV1 {
    static let adapterNeverReadsProtectedCapabilityArtifacts = true
    static let adapterNeverPersistsProfileOrSessionState = true
    static let adapterNeverPersistsPrivacyApprovalState = true
    static let adapterNeverCreatesCanonicalMutationReceipts = true
}

enum C49WorkResourcePortableExchangeIsolationV1 {
    static let sessionStoreOwnsNoWorkResourceOrDirectCostTruth = true
    static let internalCostsAreNeverPortableReviewPayload = true
    static let C48BackupSnapshotSemanticsRemainUnchanged = true
}

struct PortableExchangeSessionResponseInputV2: Sendable {
    let sessionID: UUID
    let responsePublicID: String
    let responseBytes: Data
    let disposition: ReviewResponseDispositionV1

    init(
        sessionID: UUID,
        responsePublicID: String,
        responseBytes: Data,
        disposition: ReviewResponseDispositionV1
    ) {
        self.sessionID = sessionID
        self.responsePublicID = responsePublicID
        self.responseBytes = responseBytes
        self.disposition = disposition
    }
}

struct PortableExchangeSessionStoreStatisticsV2: Codable, Equatable, Sendable {
    let namespace: PortableExchangeSessionNamespaceV2
    let sessionCount: Int
    let immutableByteCount: UInt64
    let quarantineByteCount: UInt64
    let activeCapabilityCount: Int
}

struct PortableExchangeImportPreviewV2: Equatable, Sendable {
    let requestPublicID: String
    let responsePublicID: String
    let disposition: ExternalReviewImportDispositionV1
    let proofAssessment: ReviewProofAssessmentV1
}

struct PortableExchangeImportReceiptV2: Codable, Equatable, Sendable {
    let operationID: UUID
    let responsePublicID: String
    let decision: ExternalReviewImportDecisionV1
    let resultingState: PortableExchangeSessionStateV2?
    let proofAssessment: ReviewProofAssessmentV1
    let appliedToCanonicalC14: Bool
}

protocol PortableExchangeSessionStorePortV2: Sendable {
    func sessions(
        in namespace: PortableExchangeSessionNamespaceV2?
    ) async throws -> [PortableExchangeSessionRecordV2]
    func snapshotForBackup() async throws -> PortableExchangeBackupSnapshotV2
    func replaceRestore(
        with snapshot: PortableExchangeBackupSnapshotV2,
        operationID: UUID
    ) async throws -> PortableExchangeRestoreReceiptV2
    func markClonedOrForked(
        operationID: UUID,
        resultGenerationID: UUID
    ) async throws -> PortableExchangeCloneForkReceiptV2
    func erase(operationID: UUID) async throws -> PortableExchangeEraseReceiptV2
}

/// The sole C48 owner of REVIEW and SERVICE_REQUEST exchange staging.
///
/// The actor owns only protected, operation-scoped staging.  It never inserts
/// SwiftData rows and never applies a C14 review mutation.  Callers hand an
/// accepted response to the existing canonical writer after the explicit
/// preview/decision boundary.
actor PortableExchangeSessionStoreV2: PortableExchangeSessionStorePortV2 {
    private let rootURL: URL
    private let envelopeURL: URL
    private let journalURL: URL
    private let migrationReceiptURL: URL
    private let payloadRootURL: URL
    private let capabilityRootURL: URL
    private let quarantineRootURL: URL
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource
    private let fileManager: FileManager

    private var loaded = false
    private var envelope: PortableExchangeSessionEnvelopeV2?
    private var lastMigrationReceipt: PortableExchangeSessionMigrationReceiptV2?

    init(
        applicationSupportURL: URL,
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource(),
        fileManager: FileManager = .default
    ) throws {
        guard applicationSupportURL.isFileURL else {
            throw PortableExchangePersistenceFailureV2.invalidRoot
        }
        let support = applicationSupportURL.standardizedFileURL
        rootURL = support.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.directoryName,
            isDirectory: true
        )
        envelopeURL = rootURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.envelopeFileName,
            isDirectory: false
        )
        journalURL = rootURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.journalFileName,
            isDirectory: false
        )
        migrationReceiptURL = rootURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.migrationReceiptFileName,
            isDirectory: false
        )
        payloadRootURL = rootURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.payloadDirectoryName,
            isDirectory: true
        )
        capabilityRootURL = rootURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.capabilityDirectoryName,
            isDirectory: true
        )
        quarantineRootURL = rootURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.quarantineDirectoryName,
            isDirectory: true
        )
        self.clock = clock
        self.idSource = idSource
        self.fileManager = fileManager
    }

    // MARK: - Read and stage

    func sessions(
        in namespace: PortableExchangeSessionNamespaceV2? = nil
    ) throws -> [PortableExchangeSessionRecordV2] {
        try ensureLoaded()
        let values = envelope?.sessions ?? []
        return values
            .filter { namespace == nil || $0.namespace == namespace }
            .sorted(by: Self.sessionOrder)
    }

    func session(
        id: UUID
    ) throws -> PortableExchangeSessionRecordV2? {
        try ensureLoaded()
        return envelope?.sessions.first { $0.sessionID == id }
    }

    func session(
        publicRequestID: String,
        namespace: PortableExchangeSessionNamespaceV2 = .review
    ) throws -> PortableExchangeSessionRecordV2? {
        try ensureLoaded()
        return envelope?.sessions.first {
            $0.namespace == namespace && $0.publicRequestID == publicRequestID
        }
    }

    @discardableResult
    func stage(
        _ input: PortableExchangeSessionStageInputV2
    ) throws -> PortableExchangeSessionRecordV2 {
        try ensureLoaded()
        try validateStageInput(input)
        let id = input.sessionID ?? idSource.makeID()
        if let existing = envelope?.sessions.first(where: { $0.sessionID == id }) {
            guard existing.namespace == input.namespace,
                  existing.publicRequestID == input.publicRequestID,
                  existing.revision == input.revision else {
                throw PortableExchangePersistenceFailureV2.duplicateSession
            }
            return existing
        }
        guard envelope?.sessions.contains(where: {
            $0.namespace == input.namespace &&
                $0.publicRequestID == input.publicRequestID
        }) == false else {
            throw PortableExchangePersistenceFailureV2.duplicateSession
        }

        let now = clock.now()
        let manifestReference = try input.requestManifestBytes.map {
            try persistImmutableBytes(
                $0,
                role: .requestManifest,
                sessionID: id
            )
        }
        let packageReference = try input.requestPackageBytes.map {
            try persistImmutableBytes(
                $0,
                role: .requestPackage,
                sessionID: id
            )
        }
        let capabilityReference = try input.capability.map {
            try persistCapability($0, sessionID: id, state: capabilityState(for: input.state))
        }
        let record = try PortableExchangeSessionRecordV2(
            sessionID: id,
            namespace: input.namespace,
            publicRequestID: input.publicRequestID,
            revision: input.revision,
            workspaceID: input.workspaceID,
            canonicalReviewIdentity: input.canonicalReviewIdentity,
            canonicalSubjectIdentity: input.canonicalSubjectIdentity,
            protocolReleaseDigest: input.protocolReleaseDigest,
            createdAt: now,
            updatedAt: now,
            state: input.state,
            capabilityState: capabilityState(for: input.state),
            attemptCount: 0,
            immutableBytes: [manifestReference, packageReference].compactMap { $0 },
            protectedCapability: capabilityReference,
            responseIDs: [],
            requestManifestSHA256: manifestReference?.sha256,
            requestPackageSHA256: packageReference?.sha256,
            acceptedResponseSHA256: nil,
            cloneOrForkGenerationID: nil,
            escapedCopyAcknowledged: false
        )
        try appendAndPublish(record, operation: .stage)
        return record
    }

    @discardableResult
    func stage(
        sessionID: UUID? = nil,
        namespace: PortableExchangeSessionNamespaceV2 = .review,
        publicRequestID: String,
        revision: Int = 1,
        workspaceID: UUID? = nil,
        canonicalReviewIdentity: String? = nil,
        canonicalSubjectIdentity: String? = nil,
        protocolReleaseDigest: Data? = nil,
        requestManifestBytes: Data? = nil,
        requestPackageBytes: Data? = nil,
        capability: BearerResponseCapabilityV1? = nil,
        state: PortableExchangeSessionStateV2 = .openUnexported
    ) throws -> PortableExchangeSessionRecordV2 {
        try stage(PortableExchangeSessionStageInputV2(
            sessionID: sessionID,
            namespace: namespace,
            publicRequestID: publicRequestID,
            revision: revision,
            workspaceID: workspaceID,
            canonicalReviewIdentity: canonicalReviewIdentity,
            canonicalSubjectIdentity: canonicalSubjectIdentity,
            protocolReleaseDigest: protocolReleaseDigest,
            requestManifestBytes: requestManifestBytes,
            requestPackageBytes: requestPackageBytes,
            capability: capability,
            state: state
        ))
    }

    @discardableResult
    func markExported(id: UUID) throws -> PortableExchangeSessionRecordV2 {
        try ensureLoaded()
        guard var current = envelope?.sessions.first(where: { $0.sessionID == id }) else {
            throw PortableExchangePersistenceFailureV2.sessionNotFound
        }
        guard current.state == .openUnexported,
              current.capabilityState == .issuedNotExported else {
            if current.state == .exportedAwaitingResponse { return current }
            throw PortableExchangePersistenceFailureV2.invalidTransition
        }
        guard current.protectedCapability != nil else {
            throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
        }
        current.state = .exportedAwaitingResponse
        current.capabilityState = .exportedAccepting
        current.updatedAt = clock.now()
        try replaceRecordAndPublish(current, operation: .stage)
        return current
    }

    // MARK: - Preview and response recording

    func previewImport(
        _ response: ReviewResponseEnvelopeV1,
        capability: BearerResponseCapabilityV1? = nil
    ) throws -> PortableExchangeImportPreviewV2 {
        try ensureLoaded()
        try response.validate()
        guard let record = envelope?.sessions.first(where: {
            $0.namespace == .review &&
                $0.publicRequestID == response.requestPublicID.rawValue
        }) else {
            return PortableExchangeImportPreviewV2(
                requestPublicID: response.requestPublicID.rawValue,
                responsePublicID: response.responsePublicID,
                disposition: .unknownRequest,
                proofAssessment: ReviewProofAssessmentV1(
                    proofValidity: .unavailable,
                    applicationEligibility: .unavailable
                )
            )
        }

        let responseBytes = try canonicalResponseBytes(response)
        let responseDigest = StoreMigrationCanonicalJSONV1.sha256(responseBytes)
        let matchingResponse = record.responseIDs.contains(response.responsePublicID)
        if matchingResponse {
            guard record.acceptedResponseSHA256 == responseDigest else {
                return PortableExchangeImportPreviewV2(
                    requestPublicID: response.requestPublicID.rawValue,
                    responsePublicID: response.responsePublicID,
                    disposition: .divergentSameResponseID,
                    proofAssessment: ReviewProofAssessmentV1(
                        proofValidity: .invalid,
                        applicationEligibility: .closed
                    )
                )
            }
            return PortableExchangeImportPreviewV2(
                requestPublicID: response.requestPublicID.rawValue,
                responsePublicID: response.responsePublicID,
                disposition: .duplicateAlreadyApplied,
                proofAssessment: ReviewProofAssessmentV1(
                    proofValidity: .valid,
                    applicationEligibility: .closed
                )
            )
        }

        let eligibility: ReviewApplicationEligibilityV1
        switch record.state {
        case .superseded, .historyOnlySuperseded:
            eligibility = .superseded
        case .approvalResponseRecorded,
             .changesResponseRecorded,
             .closedWithoutResponse,
             .historyOnlyTerminal,
             .historyOnlyClonedOrForked,
             .erased:
            eligibility = .closed
        case .openUnexported,
             .exportedAwaitingResponse,
             .responsePendingDecision,
             .acknowledgedAwaitingDecision,
             .quarantined,
             .erasePending:
            eligibility = .eligible
        }

        let proofValidity: ReviewProofValidityV1
        if let capability,
           let manifestDigest = record.requestManifestSHA256,
           let packageDigest = record.requestPackageSHA256,
           let manifestBytes = Self.hexData(manifestDigest),
           let packageBytes = Self.hexData(packageDigest),
           let protocolReleaseDigest = record.protocolReleaseDigest,
           protocolReleaseDigest.count == PortableReviewLimitsV1.digestByteCount {
            let input = try ReviewCapabilityProofInputV1(
                protocolReleaseDigest: protocolReleaseDigest,
                requestPublicID: response.requestPublicID,
                requestManifestDigest: manifestBytes,
                innerRequestPackageDigest: packageBytes,
                canonicalResponseBodyDigest: response.canonicalBodyDigest
            )
            proofValidity = (try ReviewCapabilityProofCodecV1.verify(
                response.proof,
                capability: capability,
                input: input
            )) ? .valid : .invalid
        } else {
            proofValidity = .unavailable
        }

        let disposition: ExternalReviewImportDispositionV1
        if proofValidity == .invalid {
            disposition = .capabilityProofInvalid
        } else if eligibility == .superseded {
            disposition = .supersededRequest
        } else if eligibility == .closed {
            disposition = .staleLocalRevision
        } else {
            disposition = .exactPendingDecision
        }
        return PortableExchangeImportPreviewV2(
            requestPublicID: response.requestPublicID.rawValue,
            responsePublicID: response.responsePublicID,
            disposition: disposition,
            proofAssessment: ReviewProofAssessmentV1(
                proofValidity: proofValidity,
                applicationEligibility: eligibility
            )
        )
    }

    /// Preview is zero-write.  This method performs the explicit decision
    /// boundary and stores exact response bytes only after it is crossed.
    @discardableResult
    func applyImport(
        _ response: ReviewResponseEnvelopeV1,
        decision: ExternalReviewImportDecisionV1,
        capability: BearerResponseCapabilityV1? = nil,
        operationID: UUID = UUID()
    ) throws -> PortableExchangeImportReceiptV2 {
        let plan = try previewImport(response, capability: capability)
        switch decision {
        case .discardUnimported:
            return PortableExchangeImportReceiptV2(
                operationID: operationID,
                responsePublicID: response.responsePublicID,
                decision: decision,
                resultingState: nil,
                proofAssessment: plan.proofAssessment,
                appliedToCanonicalC14: false
            )
        case .keepQuarantined:
            try quarantine(
                try canonicalResponseBytes(response),
                namespace: .review,
                reason: plan.disposition.rawValue
            )
            return PortableExchangeImportReceiptV2(
                operationID: operationID,
                responsePublicID: response.responsePublicID,
                decision: decision,
                resultingState: nil,
                proofAssessment: plan.proofAssessment,
                appliedToCanonicalC14: false
            )
        case .recordAsHistoryOnly:
            let record = try recordResponse(
                sessionID: try requireSession(for: response.requestPublicID),
                responsePublicID: response.responsePublicID,
                responseBytes: try canonicalResponseBytes(response),
                disposition: response.body.disposition,
                historyOnly: true
            )
            return PortableExchangeImportReceiptV2(
                operationID: operationID,
                responsePublicID: response.responsePublicID,
                decision: decision,
                resultingState: record.state,
                proofAssessment: plan.proofAssessment,
                appliedToCanonicalC14: false
            )
        case .acceptAndApply:
            guard plan.disposition == .exactPendingDecision,
                  plan.proofAssessment.applicationEligibility == .eligible else {
                throw PortableExchangePersistenceFailureV2.invalidTransition
            }
            let record = try recordResponse(
                sessionID: try requireSession(for: response.requestPublicID),
                responsePublicID: response.responsePublicID,
                responseBytes: try canonicalResponseBytes(response),
                disposition: response.body.disposition,
                historyOnly: false
            )
            return PortableExchangeImportReceiptV2(
                operationID: operationID,
                responsePublicID: response.responsePublicID,
                decision: decision,
                resultingState: record.state,
                proofAssessment: plan.proofAssessment,
                appliedToCanonicalC14: false
            )
        }
    }

    @discardableResult
    func recordResponse(
        _ input: PortableExchangeSessionResponseInputV2,
        historyOnly: Bool = false
    ) throws -> PortableExchangeSessionRecordV2 {
        try recordResponse(
            sessionID: input.sessionID,
            responsePublicID: input.responsePublicID,
            responseBytes: input.responseBytes,
            disposition: input.disposition,
            historyOnly: historyOnly
        )
    }

    @discardableResult
    func recordResponse(
        sessionID: UUID,
        responsePublicID: String,
        responseBytes: Data,
        disposition: ReviewResponseDispositionV1,
        historyOnly: Bool = false
    ) throws -> PortableExchangeSessionRecordV2 {
        try ensureLoaded()
        guard var current = envelope?.sessions.first(where: { $0.sessionID == sessionID }) else {
            throw PortableExchangePersistenceFailureV2.sessionNotFound
        }
        try PortableReviewLimitsV1.canonicalASCII(responsePublicID)
        guard !responseBytes.isEmpty,
              responseBytes.count <= PortableReviewLimitsV1.maximumResponseBytes else {
            throw PortableExchangePersistenceFailureV2.invalidPayload
        }
        guard !current.state.isImmutableHistory,
              current.state != .quarantined,
              current.state != .erasePending,
              current.state != .erased else {
            if current.responseIDs.contains(responsePublicID),
               current.acceptedResponseSHA256 == StoreMigrationCanonicalJSONV1.sha256(responseBytes) {
                return current
            }
            throw PortableExchangePersistenceFailureV2.invalidTransition
        }
        let responseDigest = StoreMigrationCanonicalJSONV1.sha256(responseBytes)
        if let index = current.responseIDs.firstIndex(of: responsePublicID) {
            guard current.acceptedResponseSHA256 == responseDigest else {
                throw PortableExchangePersistenceFailureV2.duplicateSession
            }
            return current
        }
        let reference = try persistImmutableBytes(
            responseBytes,
            role: .acceptedResponse,
            sessionID: sessionID
        )
        current.immutableBytes.append(reference)
        current.responseIDs.append(responsePublicID)
        current.acceptedResponseSHA256 = responseDigest
        current.state = historyOnly ? .historyOnlyTerminal : state(for: disposition)
        if historyOnly || disposition != .acknowledged {
            current.capabilityState = .historyOnlyTerminal
            if current.protectedCapability != nil {
                try removeCapability(for: current)
                current.protectedCapability = nil
            }
        } else {
            // Acknowledgement is not a terminal decision.  Keep the
            // protected capability and mark the session pending decision.
            current.capabilityState = .responsePendingDecision
        }
        current.updatedAt = clock.now()
        try replaceRecordAndPublish(current, operation: .accept)
        return current
    }

    func recordOriginResponse(
        sessionID: UUID,
        response: OriginRecordedReviewResponseV1
    ) throws -> PortableExchangeSessionRecordV2 {
        try response.validate()
        let bodyBytes = try PortableReviewCanonicalCodecV1.responseRecordBytes(
            .originRecorded(response)
        )
        return try recordResponse(
            sessionID: sessionID,
            responsePublicID: "origin-\(response.recordedByActorID.uuidString.lowercased())-\(Int(response.recordedAt.timeIntervalSince1970))",
            responseBytes: bodyBytes,
            disposition: response.responseBody.disposition,
            historyOnly: true
        )
    }

    // MARK: - Backup and restore

    /// Synchronous disk-only projection for backup owners that cannot bridge
    /// an actor.  It performs the same fail-closed digest/path checks as the
    /// actor snapshot and never mutates, migrates, or deletes the store.
    nonisolated static func snapshotForBackup(
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) throws -> PortableExchangeBackupSnapshotV2 {
        guard applicationSupportURL.isFileURL else {
            throw PortableExchangePersistenceFailureV2.invalidRoot
        }
        let rootURL = applicationSupportURL.standardizedFileURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.directoryName,
            isDirectory: true
        )
        let envelopeURL = rootURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.envelopeFileName,
            isDirectory: false
        )
        guard fileManager.fileExists(atPath: envelopeURL.path) else {
            return try PortableExchangeBackupSnapshotV2(
                createdAt: Date(),
                sessions: [],
                immutablePayloads: [],
                protectedCapabilityArtifacts: []
            )
        }
        let data = try staticRead(
            envelopeURL,
            kind: .portableExchangeSessionFile,
            maximumByteCount: C48PortableReviewPersistenceLimitsV1.maximumEnvelopeBytes
        )
        let version = try staticStoreVersion(in: data)
        let current: PortableExchangeSessionEnvelopeV2
        switch version {
        case 1:
            let old = try StoreMigrationCanonicalJSONV1.decodeCanonical(
                PortableExchangeSessionEnvelopeV1.self,
                from: data
            )
            current = try PortableExchangeSessionEnvelopeV2(
                generationID: old.generationID,
                updatedAt: old.updatedAt,
                sessions: old.sessions,
                quarantine: old.quarantine
            ).canonicalSorted()
        case 2:
            current = try StoreMigrationCanonicalJSONV1.decodeCanonical(
                PortableExchangeSessionEnvelopeV2.self,
                from: data
            ).canonicalSorted()
        default:
            throw PortableExchangePersistenceFailureV2.unsupportedSchemaVersion
        }
        var payloads: [PortableExchangeImmutablePayloadV2] = []
        var seenPayloads = Set<String>()
        var capabilities: [PortableExchangeProtectedCapabilityBackupV2] = []
        let eligibleSessions = current.sessions.filter {
            $0.state != .quarantined && $0.state != .erased
        }
        for session in eligibleSessions {
            for reference in session.immutableBytes {
                let bytes = try staticRead(
                    try staticSafeURL(reference.relativePath, rootURL: rootURL),
                    kind: .portableExchangeSessionFile,
                    maximumByteCount: C48PortableReviewPersistenceLimitsV1.maximumImmutableBytes
                )
                guard UInt64(bytes.count) == reference.byteCount,
                      StoreMigrationCanonicalJSONV1.sha256(bytes) == reference.sha256 else {
                    throw PortableExchangePersistenceFailureV2.corruptStore
                }
                let key = "\(reference.role.rawValue):\(reference.sha256)"
                if seenPayloads.insert(key).inserted {
                    payloads.append(try PortableExchangeImmutablePayloadV2(
                        role: reference.role,
                        bytes: bytes
                    ))
                }
            }
            if let artifact = session.protectedCapability {
                let bytes = try staticRead(
                    try staticSafeURL(artifact.relativePath, rootURL: rootURL),
                    kind: .portableExchangeSessionFile,
                    maximumByteCount: PortableReviewLimitsV1.capabilityByteCount
                )
                guard bytes.count == PortableReviewLimitsV1.capabilityByteCount,
                      StoreMigrationCanonicalJSONV1.sha256(bytes) == artifact.sha256 else {
                    throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
                }
                capabilities.append(try PortableExchangeProtectedCapabilityBackupV2(
                    sessionID: session.sessionID,
                    bytes: bytes,
                    state: session.capabilityState
                ))
            } else if session.capabilityState == .exportedAccepting ||
                      session.capabilityState == .responsePendingDecision {
                throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
            }
        }
        return try PortableExchangeBackupSnapshotV2(
            createdAt: Date(),
            sessions: eligibleSessions,
            immutablePayloads: payloads,
            protectedCapabilityArtifacts: capabilities
        )
    }

    /// Returns the digest of the exact current envelope bytes used as the
    /// replace/restore preimage. An absent envelope is represented by the
    /// digest of empty data, matching the journal's empty-store convention.
    /// The bytes are decoded and validated before their digest is exposed so a
    /// sidecar can never authorize recovery from an unreadable image.
    nonisolated static func recoveryStateSHA256(
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) throws -> String {
        guard applicationSupportURL.isFileURL else {
            throw PortableExchangePersistenceFailureV2.invalidRoot
        }
        let rootURL = applicationSupportURL.standardizedFileURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.directoryName,
            isDirectory: true
        )
        let envelopeURL = rootURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.envelopeFileName,
            isDirectory: false
        )
        guard fileManager.fileExists(atPath: envelopeURL.path) else {
            return StoreMigrationCanonicalJSONV1.sha256(Data())
        }
        let data = try staticRead(
            envelopeURL,
            kind: .portableExchangeSessionFile,
            maximumByteCount: C48PortableReviewPersistenceLimitsV1.maximumEnvelopeBytes
        )
        _ = try staticDecodeEnvelope(data)
        return StoreMigrationCanonicalJSONV1.sha256(data)
    }

    /// Synchronous startup-recovery entry point for a protected backup
    /// sidecar. The caller must already hold the app's startup/recovery
    /// exclusivity. Recovery is authorized only from the exact preimage
    /// captured in the sidecar, or is an idempotent no-op when the exact target
    /// image is already present. A third image is divergence, never an
    /// invitation to overwrite local state.
    nonisolated static func restoreSnapshotForRecovery(
        applicationSupportURL: URL,
        snapshot: PortableExchangeBackupSnapshotV2,
        operationID: UUID,
        expectedResultGenerationID: UUID,
        cloneOrFork: Bool,
        expectedBeforeEnvelopeSHA256: String,
        fileManager: FileManager = .default
    ) throws -> PortableExchangeRestoreReceiptV2 {
        guard applicationSupportURL.isFileURL,
              operationID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              expectedResultGenerationID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else {
            throw PortableExchangePersistenceFailureV2.invalidTransition
        }
        guard StoreMigrationCanonicalJSONV1.isLowercaseSHA256(
            expectedBeforeEnvelopeSHA256
        ) else {
            throw PortableExchangePersistenceFailureV2.invalidTransition
        }
        try snapshot.validate()
        try PortableExchangeProtectedFilePolicyV2.validate()

        let supportURL = applicationSupportURL.standardizedFileURL
        let rootURL = supportURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.directoryName,
            isDirectory: true
        )
        let envelopeURL = rootURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.envelopeFileName,
            isDirectory: false
        )
        let journalURL = rootURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.journalFileName,
            isDirectory: false
        )
        let payloadRootURL = rootURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.payloadDirectoryName,
            isDirectory: true
        )
        let capabilityRootURL = rootURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.capabilityDirectoryName,
            isDirectory: true
        )
        let quarantineRootURL = rootURL.appendingPathComponent(
            PortableExchangeSessionStoreLayoutV2.quarantineDirectoryName,
            isDirectory: true
        )

        try staticEnsureDirectory(
            rootURL,
            fileManager: fileManager,
            intermediate: true
        )
        try staticEnsureDirectory(payloadRootURL, fileManager: fileManager)
        try staticEnsureDirectory(capabilityRootURL, fileManager: fileManager)
        try staticEnsureDirectory(quarantineRootURL, fileManager: fileManager)

        var existingJournal: PortableExchangeJournalEntryV2?
        var existingJournalData: Data?
        if fileManager.fileExists(atPath: journalURL.path) {
            let journalData = try staticRead(
                journalURL,
                kind: .portableExchangeJournalFile,
                maximumByteCount: 64 * 1_024
            )
            let journal = try StoreMigrationCanonicalJSONV1.decodeCanonical(
                PortableExchangeJournalEntryV2.self,
                from: journalData
            )
            guard journal.operationID == operationID,
                  journal.operation == .restore,
                  journal.phase == .prepared || journal.phase == .committed else {
                throw PortableExchangePersistenceFailureV2.invalidJournal
            }
            existingJournal = journal
            existingJournalData = journalData
        }

        let existingData: Data? = fileManager.fileExists(atPath: envelopeURL.path)
            ? try staticRead(
                envelopeURL,
                kind: .portableExchangeSessionFile,
                maximumByteCount: C48PortableReviewPersistenceLimitsV1.maximumEnvelopeBytes
            )
            : nil
        let existingEnvelope = try existingData.map {
            try staticDecodeEnvelope($0)
        }

        let payloadsByKey = try staticPayloadMap(snapshot.immutablePayloads)
        let capabilityBySession = try staticCapabilityMap(
            snapshot.protectedCapabilityArtifacts
        )
        let targetSessions = try staticRecoverySessions(
            snapshot.sessions,
            capabilities: capabilityBySession,
            expectedResultGenerationID: expectedResultGenerationID,
            cloneOrFork: cloneOrFork
        )
        let targetEnvelope = try PortableExchangeSessionEnvelopeV2(
            generationID: expectedResultGenerationID,
            updatedAt: snapshot.createdAt,
            sessions: targetSessions,
            quarantine: []
        ).canonicalSorted()
        let targetData = try StoreMigrationCanonicalJSONV1.encode(targetEnvelope)
        let beforeData = existingData ?? Data()
        let beforeSHA256 = StoreMigrationCanonicalJSONV1.sha256(beforeData)
        let afterSHA256 = StoreMigrationCanonicalJSONV1.sha256(targetData)
        guard beforeSHA256 == expectedBeforeEnvelopeSHA256 ||
              beforeSHA256 == afterSHA256 else {
            throw PortableExchangePersistenceFailureV2.corruptStore
        }
        let replayingPreparedTarget = beforeSHA256 == afterSHA256 &&
            existingJournal?.phase == .prepared
        if let existingJournal {
            guard existingJournal.beforeSHA256 == expectedBeforeEnvelopeSHA256,
                  existingJournal.afterSHA256 == afterSHA256,
                  beforeSHA256 == existingJournal.beforeSHA256 ||
                      beforeSHA256 == existingJournal.afterSHA256 else {
                throw PortableExchangePersistenceFailureV2.corruptStore
            }
        }
        if beforeSHA256 == afterSHA256 {
            guard existingEnvelope == targetEnvelope else {
                throw PortableExchangePersistenceFailureV2.corruptStore
            }
        }

        let prepared = try PortableExchangeJournalEntryV2(
            operationID: operationID,
            operation: .restore,
            namespace: nil,
            sessionID: nil,
            beforeSHA256: expectedBeforeEnvelopeSHA256,
            afterSHA256: afterSHA256,
            phase: .prepared,
            createdAt: snapshot.createdAt
        )
        let preparedData = try StoreMigrationCanonicalJSONV1.encode(prepared)
        if existingJournalData == nil {
            try staticWriteAndFsyncAtomically(
                preparedData,
                to: journalURL,
                kind: .portableExchangeJournalFile,
                fileManager: fileManager,
                operationID: operationID
            )
            existingJournalData = preparedData
        }

        var referencedPayloadKeys = Set<String>()
        for source in snapshot.sessions {
            for reference in source.immutableBytes {
                let key = "\(reference.role.rawValue):\(reference.sha256)"
                guard let bytes = payloadsByKey[key],
                      StoreMigrationCanonicalJSONV1.sha256(bytes) == reference.sha256,
                      UInt64(bytes.count) == reference.byteCount,
                      reference.relativePath.hasPrefix(
                          "\(PortableExchangeSessionStoreLayoutV2.payloadDirectoryName)/"
                      ) else {
                    throw PortableExchangePersistenceFailureV2.invalidBackupSnapshot
                }
                referencedPayloadKeys.insert(key)
                let url = try staticSafeURL(reference.relativePath, rootURL: rootURL)
                try staticWriteAtomically(
                    bytes,
                    to: url,
                    kind: .portableExchangeSessionFile,
                    fileManager: fileManager,
                    operationID: operationID
                )
            }
        }
        guard referencedPayloadKeys == Set(payloadsByKey.keys) else {
            throw PortableExchangePersistenceFailureV2.invalidBackupSnapshot
        }

        let existingCapabilitiesBySession: [UUID: PortableExchangeProtectedCapabilityArtifactV2] =
            Dictionary(uniqueKeysWithValues: (existingEnvelope?.sessions ?? []).compactMap { session in
                guard let artifact = session.protectedCapability else { return nil }
                return (session.sessionID, artifact)
            })
        let sourceSessionsByID: [UUID: PortableExchangeSessionRecordV2] =
            Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.sessionID, $0) })
        let expectedCapabilityIDs = Set(
            snapshot.sessions.compactMap { $0.protectedCapability == nil ? nil : $0.sessionID }
        )
        guard Set(capabilityBySession.keys) == expectedCapabilityIDs else {
            throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
        }
        let recoveryOldStagesBySession: [UUID: URL]
        if existingJournal?.phase == .prepared {
            recoveryOldStagesBySession = try staticRecoveryOldStageURLs(
                capabilityRootURL: capabilityRootURL,
                operationID: operationID,
                fileManager: fileManager
            )
        } else {
            recoveryOldStagesBySession = [:]
        }
        let capabilityPlanIDs = Set(existingCapabilitiesBySession.keys)
            .union(expectedCapabilityIDs)
            .union(recoveryOldStagesBySession.keys)
        var capabilityPlans: [PortableExchangeStaticRecoveryCapabilityPlan] = []
        for sessionID in capabilityPlanIDs.sorted(by: {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        }) {
            let source = sourceSessionsByID[sessionID]
            let sourceArtifact = source?.protectedCapability
            let backup = sourceArtifact.flatMap { capabilityBySession[sessionID] }
            if let sourceArtifact {
                guard let source,
                      let backup,
                      backup.state == source.capabilityState,
                      backup.bytes.count == PortableReviewLimitsV1.capabilityByteCount,
                      StoreMigrationCanonicalJSONV1.sha256(backup.bytes) == sourceArtifact.sha256,
                      sourceArtifact.relativePath.hasPrefix(
                          "\(PortableExchangeSessionStoreLayoutV2.capabilityDirectoryName)/"
                      ) else {
                    throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
                }
            } else {
                guard backup == nil else {
                    throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
                }
            }
            let canonicalRelativePath =
                "\(PortableExchangeSessionStoreLayoutV2.capabilityDirectoryName)/\(sessionID.uuidString.lowercased()).bin"
            if let sourceArtifact {
                guard sourceArtifact.relativePath == canonicalRelativePath else {
                    throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
                }
            }
            if let oldArtifact = existingCapabilitiesBySession[sessionID] {
                guard oldArtifact.relativePath == canonicalRelativePath else {
                    throw PortableExchangePersistenceFailureV2.corruptStore
                }
            }
            let targetArtifact = cloneOrFork ? nil : sourceArtifact
            let targetURL = try targetArtifact.map {
                try staticSafeURL($0.relativePath, rootURL: rootURL)
            }
            let oldArtifact = replayingPreparedTarget
                ? nil
                : existingCapabilitiesBySession[sessionID]
            let oldURL: URL?
            let oldBytes: Data?
            let oldStageURL: URL?
            if existingJournal?.phase == .prepared,
               let recoveryStageURL = recoveryOldStagesBySession[sessionID] {
                let stagePrefix = ".recovery-old-\(operationID.uuidString.lowercased())-\(sessionID.uuidString.lowercased())-"
                let stageName = recoveryStageURL.lastPathComponent
                let stageDigest = String(stageName.dropFirst(stagePrefix.count).dropLast(4))
                let stagedOldBytes = try staticRead(
                    recoveryStageURL,
                    kind: .portableExchangeSessionFile,
                    maximumByteCount: PortableReviewLimitsV1.capabilityByteCount
                )
                guard stageName.hasPrefix(stagePrefix),
                      stageName.hasSuffix(".bin"),
                      StoreMigrationCanonicalJSONV1.isLowercaseSHA256(stageDigest),
                      stagedOldBytes.count == PortableReviewLimitsV1.capabilityByteCount,
                      StoreMigrationCanonicalJSONV1.sha256(stagedOldBytes) == stageDigest else {
                    throw PortableExchangePersistenceFailureV2.corruptStore
                }
                let candidateOldURL = try staticSafeURL(
                    canonicalRelativePath,
                    rootURL: rootURL
                )
                if fileManager.fileExists(atPath: candidateOldURL.path) {
                    let current = try staticRead(
                        candidateOldURL,
                        kind: .portableExchangeSessionFile,
                        maximumByteCount: PortableReviewLimitsV1.capabilityByteCount
                    )
                    if current == stagedOldBytes {
                        oldURL = candidateOldURL
                        oldBytes = stagedOldBytes
                    } else if !cloneOrFork,
                              let backup,
                              current == backup.bytes {
                        // The target capability was already published while
                        // the target envelope was being replayed.  The old
                        // staged bytes remain the authorized cleanup preimage.
                        oldURL = nil
                        oldBytes = nil
                    } else {
                        throw PortableExchangePersistenceFailureV2.corruptStore
                    }
                } else {
                    oldURL = nil
                    oldBytes = nil
                }
                oldStageURL = recoveryStageURL
            } else if let oldArtifact {
                let candidateOldURL = try staticSafeURL(
                    oldArtifact.relativePath,
                    rootURL: rootURL
                )
                if !fileManager.fileExists(atPath: candidateOldURL.path) {
                    guard existingJournal?.phase == .prepared, cloneOrFork else {
                        throw PortableExchangePersistenceFailureV2.corruptStore
                    }
                    // A matching PREPARED clone/fork may have already
                    // removed the old capability before a relaunch.  The
                    // journal is the proof that this absence is authorized.
                    oldURL = nil
                    oldBytes = nil
                    oldStageURL = nil
                } else {
                    let bytes = try staticRead(
                        candidateOldURL,
                        kind: .portableExchangeSessionFile,
                        maximumByteCount: PortableReviewLimitsV1.capabilityByteCount
                    )
                    if bytes.count == PortableReviewLimitsV1.capabilityByteCount,
                       StoreMigrationCanonicalJSONV1.sha256(bytes) == oldArtifact.sha256 {
                        let stageURL = capabilityRootURL.appendingPathComponent(
                            ".recovery-old-\(operationID.uuidString.lowercased())-\(sessionID.uuidString.lowercased())-\(oldArtifact.sha256).bin",
                            isDirectory: false
                        )
                        try staticWriteAtomically(
                            bytes,
                            to: stageURL,
                            kind: .portableExchangeSessionFile,
                            fileManager: fileManager,
                            operationID: operationID
                        )
                        oldURL = candidateOldURL
                        oldBytes = bytes
                        oldStageURL = stageURL
                    } else if !cloneOrFork,
                              let backup,
                              targetURL?.path == candidateOldURL.path,
                              bytes == backup.bytes {
                        // The envelope is still the before-image but its
                        // sessionID-keyed capability already reached target
                        // bytes, authenticated by the backup snapshot.
                        oldURL = nil
                        oldBytes = nil
                        oldStageURL = nil
                    } else {
                        throw PortableExchangePersistenceFailureV2.corruptStore
                    }
                }
            } else {
                oldURL = nil
                oldBytes = nil
                oldStageURL = nil
            }
            let targetStageURL: URL?
            if let targetArtifact, let backup {
                let stageURL = capabilityRootURL.appendingPathComponent(
                    ".recovery-target-\(operationID.uuidString.lowercased())-\(sessionID.uuidString.lowercased())-\(backup.sha256).bin",
                    isDirectory: false
                )
                try staticWriteAtomically(
                    backup.bytes,
                    to: stageURL,
                    kind: .portableExchangeSessionFile,
                    fileManager: fileManager,
                    operationID: operationID
                )
                if let targetURL,
                   let oldURL,
                   targetURL.path != oldURL.path,
                   fileManager.fileExists(atPath: targetURL.path) {
                    let current = try staticRead(
                        targetURL,
                        kind: .portableExchangeSessionFile,
                        maximumByteCount: PortableReviewLimitsV1.capabilityByteCount
                    )
                    guard current == backup.bytes else {
                        throw PortableExchangePersistenceFailureV2.corruptStore
                    }
                }
                targetStageURL = stageURL
            } else {
                targetStageURL = nil
            }
            capabilityPlans.append(PortableExchangeStaticRecoveryCapabilityPlan(
                sessionID: sessionID,
                targetArtifact: targetArtifact,
                backup: backup,
                targetURL: targetURL,
                targetStageURL: targetStageURL,
                oldArtifact: oldArtifact,
                oldURL: oldURL,
                oldBytes: oldBytes,
                oldStageURL: oldStageURL
            ))
        }

        if beforeSHA256 != afterSHA256 {
            if let existingData {
                try staticReplaceAtomically(
                    targetData,
                    to: envelopeURL,
                    expectedCurrentData: existingData,
                    kind: .portableExchangeSessionFile,
                    fileManager: fileManager,
                    operationID: operationID
                )
            } else {
                try staticWriteAndFsyncAtomically(
                    targetData,
                    to: envelopeURL,
                    kind: .portableExchangeSessionFile,
                    fileManager: fileManager,
                    operationID: operationID
                )
            }
        }

        for plan in capabilityPlans {
            let stagedTargetBytes: Data?
            if let targetStageURL = plan.targetStageURL {
                guard let backup = plan.backup else {
                    throw PortableExchangePersistenceFailureV2.corruptStore
                }
                let bytes = try staticRead(
                    targetStageURL,
                    kind: .portableExchangeSessionFile,
                    maximumByteCount: PortableReviewLimitsV1.capabilityByteCount
                )
                guard bytes == backup.bytes else {
                    throw PortableExchangePersistenceFailureV2.corruptStore
                }
                stagedTargetBytes = bytes
            } else {
                stagedTargetBytes = nil
            }
            if let targetURL = plan.targetURL,
               let stagedTargetBytes {
                if let oldURL = plan.oldURL,
                   let oldBytes = plan.oldBytes,
                   targetURL.path == oldURL.path {
                    if fileManager.fileExists(atPath: targetURL.path) {
                        let current = try staticRead(
                            targetURL,
                            kind: .portableExchangeSessionFile,
                            maximumByteCount: PortableReviewLimitsV1.capabilityByteCount
                        )
                        if current != stagedTargetBytes {
                            guard current == oldBytes else {
                                throw PortableExchangePersistenceFailureV2.corruptStore
                            }
                            try staticReplaceAtomically(
                                stagedTargetBytes,
                                to: targetURL,
                                expectedCurrentData: oldBytes,
                                kind: .portableExchangeSessionFile,
                                fileManager: fileManager,
                                operationID: operationID
                            )
                        }
                    } else {
                        try staticWriteAtomically(
                            stagedTargetBytes,
                            to: targetURL,
                            kind: .portableExchangeSessionFile,
                            fileManager: fileManager,
                            operationID: operationID
                        )
                    }
                } else {
                    try staticWriteAtomically(
                        stagedTargetBytes,
                        to: targetURL,
                        kind: .portableExchangeSessionFile,
                        fileManager: fileManager,
                        operationID: operationID
                    )
                }
                guard fileManager.fileExists(atPath: targetURL.path),
                      try staticRead(
                          targetURL,
                          kind: .portableExchangeSessionFile,
                          maximumByteCount: PortableReviewLimitsV1.capabilityByteCount
                      ) == stagedTargetBytes else {
                    throw PortableExchangePersistenceFailureV2.corruptStore
                }
            }
            if let oldURL = plan.oldURL,
               let oldBytes = plan.oldBytes,
               plan.targetURL?.path != oldURL.path {
                try staticRemoveIfExact(
                    oldURL,
                    expectedBytes: oldBytes,
                    kind: .portableExchangeSessionFile,
                    fileManager: fileManager
                )
            }
        }

        var expectedCanonicalCapabilityBytes: [String: Data] = [:]
        var recoveryStagePaths = Set<String>()
        for plan in capabilityPlans {
            if let targetURL = plan.targetURL {
                guard let backup = plan.backup else {
                    throw PortableExchangePersistenceFailureV2.corruptStore
                }
                let path = targetURL.standardizedFileURL.path
                if let existing = expectedCanonicalCapabilityBytes[path] {
                    guard existing == backup.bytes else {
                        throw PortableExchangePersistenceFailureV2.corruptStore
                    }
                } else {
                    expectedCanonicalCapabilityBytes[path] = backup.bytes
                }
            }
            if let targetStageURL = plan.targetStageURL {
                recoveryStagePaths.insert(targetStageURL.standardizedFileURL.path)
            }
            if let oldStageURL = plan.oldStageURL {
                recoveryStagePaths.insert(oldStageURL.standardizedFileURL.path)
            }
        }
        try staticValidateCanonicalCapabilityInventory(
            capabilityRootURL: capabilityRootURL,
            expectedBytesByPath: expectedCanonicalCapabilityBytes,
            ignoredRecoveryStagePaths: recoveryStagePaths,
            fileManager: fileManager
        )
        for plan in capabilityPlans {
            if let targetStageURL = plan.targetStageURL {
                try staticRemove(
                    targetStageURL,
                    kind: .portableExchangeSessionFile,
                    fileManager: fileManager
                )
            }
            if let oldStageURL = plan.oldStageURL {
                try staticRemove(
                    oldStageURL,
                    kind: .portableExchangeSessionFile,
                    fileManager: fileManager
                )
            }
        }
        try staticValidateCanonicalCapabilityInventory(
            capabilityRootURL: capabilityRootURL,
            expectedBytesByPath: expectedCanonicalCapabilityBytes,
            ignoredRecoveryStagePaths: [],
            fileManager: fileManager
        )
        if existingJournalData == nil {
            guard beforeSHA256 == afterSHA256 else {
                throw PortableExchangePersistenceFailureV2.invalidJournal
            }
            let immutableByteCount = targetSessions.reduce(UInt64(0)) {
                $0 + $1.immutableBytes.reduce(UInt64(0)) { $0 + $1.byteCount }
            }
            let activeCapabilityCount = targetSessions.filter {
                $0.protectedCapability != nil && $0.capabilityState.isActive
            }.count
            return try PortableExchangeRestoreReceiptV2(
                operationID: operationID,
                snapshotID: snapshot.snapshotID,
                restoredSessionCount: targetSessions.count,
                preservedImmutableByteCount: immutableByteCount,
                activeCapabilitiesPreserved: activeCapabilityCount,
                completedAt: snapshot.createdAt
            )
        }

        let committed = try PortableExchangeJournalEntryV2(
            operationID: operationID,
            operation: .restore,
            namespace: nil,
            sessionID: nil,
            beforeSHA256: expectedBeforeEnvelopeSHA256,
            afterSHA256: afterSHA256,
            phase: .committed,
            createdAt: prepared.createdAt
        )
        let committedData = try StoreMigrationCanonicalJSONV1.encode(committed)
        guard let currentJournalData = existingJournalData else {
            throw PortableExchangePersistenceFailureV2.invalidJournal
        }
        try staticReplaceAtomically(
            committedData,
            to: journalURL,
            expectedCurrentData: currentJournalData,
            kind: .portableExchangeJournalFile,
            fileManager: fileManager,
            operationID: operationID
        )
        try staticRemove(
            journalURL,
            kind: .portableExchangeJournalFile,
            fileManager: fileManager
        )

        let immutableByteCount = targetSessions.reduce(UInt64(0)) {
            $0 + $1.immutableBytes.reduce(UInt64(0)) { $0 + $1.byteCount }
        }
        let activeCapabilityCount = targetSessions.filter {
            $0.protectedCapability != nil && $0.capabilityState.isActive
        }.count
        return try PortableExchangeRestoreReceiptV2(
            operationID: operationID,
            snapshotID: snapshot.snapshotID,
            restoredSessionCount: targetSessions.count,
            preservedImmutableByteCount: immutableByteCount,
            activeCapabilitiesPreserved: activeCapabilityCount,
            completedAt: snapshot.createdAt
        )
    }

    func snapshotForBackup() throws -> PortableExchangeBackupSnapshotV2 {
        try ensureLoaded()
        let current = try (envelope ?? emptyEnvelope()).canonicalSorted().validated()
        var payloads: [PortableExchangeImmutablePayloadV2] = []
        var seenPayloads = Set<String>()
        var capabilityPayloads: [PortableExchangeProtectedCapabilityBackupV2] = []
        var seenCapabilities = Set<UUID>()
        let eligibleSessions = current.sessions.filter {
            $0.state != .quarantined && $0.state != .erased
        }
        for session in eligibleSessions {
            for reference in session.immutableBytes {
                let bytes = try readPayload(reference.relativePath)
                guard StoreMigrationCanonicalJSONV1.sha256(bytes) == reference.sha256,
                      UInt64(bytes.count) == reference.byteCount else {
                    throw PortableExchangePersistenceFailureV2.corruptStore
                }
                let key = "\(reference.role.rawValue):\(reference.sha256)"
                if seenPayloads.insert(key).inserted {
                    payloads.append(try PortableExchangeImmutablePayloadV2(
                        role: reference.role,
                        bytes: bytes
                    ))
                }
            }
            if let artifact = session.protectedCapability,
               seenCapabilities.insert(session.sessionID).inserted {
                let bytes = try readCapability(artifact.relativePath)
                guard bytes.count == 32,
                      StoreMigrationCanonicalJSONV1.sha256(bytes) == artifact.sha256 else {
                    throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
                }
                capabilityPayloads.append(try PortableExchangeProtectedCapabilityBackupV2(
                    sessionID: session.sessionID,
                    bytes: bytes,
                    state: session.capabilityState
                ))
            } else if session.capabilityState == .exportedAccepting ||
                      session.capabilityState == .responsePendingDecision {
                throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
            }
        }
        return try PortableExchangeBackupSnapshotV2(
            createdAt: clock.now(),
            sessions: eligibleSessions,
            immutablePayloads: payloads,
            protectedCapabilityArtifacts: capabilityPayloads
        )
    }

    func replaceRestore(
        with snapshot: PortableExchangeBackupSnapshotV2,
        operationID: UUID = UUID()
    ) throws -> PortableExchangeRestoreReceiptV2 {
        try ensureLoaded()
        try snapshot.validate()
        let next = try restoredEnvelope(from: snapshot)
        let activeCapabilityCount = next.sessions.filter {
            $0.capabilityState.isActive && $0.protectedCapability != nil
        }.count
        let immutableByteCount = next.sessions.reduce(UInt64(0)) {
            $0 + $1.immutableBytes.reduce(UInt64(0)) { $0 + $1.byteCount }
        }
        try publishEnvelope(
            next,
            operation: .restore,
            operationID: operationID,
            namespace: nil,
            sessionID: nil
        )
        envelope = next
        let receipt = try PortableExchangeRestoreReceiptV2(
            operationID: operationID,
            snapshotID: snapshot.snapshotID,
            restoredSessionCount: next.sessions.count,
            preservedImmutableByteCount: immutableByteCount,
            activeCapabilitiesPreserved: activeCapabilityCount,
            completedAt: clock.now()
        )
        return receipt
    }

    // MARK: - Clone, fork, delete, and Erase

    /// Invalidates only active sessions whose internal workspace mapping is an
    /// exact match.  Immutable request/response bytes remain available as
    /// history; no unscoped cleanup is permitted when a mapping is absent.
    @discardableResult
    func invalidateSessionsForDeletedWorkspace(
        workspaceID: WorkspaceID,
        operationID: UUID = UUID()
    ) throws -> Int {
        try invalidateSessions(
            matching: { $0.workspaceID == workspaceID.rawValue },
            operationID: operationID
        )
    }

    /// Invalidates only active sessions for one exact C14 subject identity in
    /// the supplied workspace.  The subject ID is internal and is never
    /// serialized into portable exchange bytes.
    @discardableResult
    func invalidateSessionsForDeletedSubject(
        workspaceID: WorkspaceID,
        subjectID: String,
        operationID: UUID = UUID()
    ) throws -> Int {
        guard C48PortableReviewPersistenceValidationV1.validInternalIdentity(subjectID) else {
            throw PortableExchangePersistenceFailureV2.invalidRecord
        }
        return try invalidateSessions(
            matching: {
                $0.workspaceID == workspaceID.rawValue &&
                    $0.canonicalSubjectIdentity == subjectID
            },
            operationID: operationID
        )
    }

    /// Explicit alias for deletion owners.  It deliberately performs the
    /// same exact-match, history-preserving invalidation as the subject API.
    @discardableResult
    func invalidateForDeletedSubject(
        workspaceID: WorkspaceID,
        subjectID: String,
        operationID: UUID = UUID()
    ) throws -> Int {
        try invalidateSessionsForDeletedSubject(
            workspaceID: workspaceID,
            subjectID: subjectID,
            operationID: operationID
        )
    }

    @discardableResult
    func eraseAll(
        operationID: UUID = UUID()
    ) throws -> PortableExchangeEraseReceiptV2 {
        try erase(operationID: operationID)
    }

    private func invalidateSessions(
        matching predicate: (PortableExchangeSessionRecordV2) -> Bool,
        operationID: UUID
    ) throws -> Int {
        try ensureLoaded()
        var next = try envelope ?? emptyEnvelope()
        var changed = 0
        for index in next.sessions.indices where predicate(next.sessions[index]) {
            guard next.sessions[index].capabilityState.isActive,
                  next.sessions[index].protectedCapability != nil else { continue }
            next.sessions[index].state = .historyOnlySuperseded
            next.sessions[index].capabilityState = .historyOnlySuperseded
            next.sessions[index].pendingMutationID = nil
            next.sessions[index].pendingEffectSHA256 = nil
            next.sessions[index].pendingImportReceiptSHA256 = nil
            next.sessions[index].updatedAt = clock.now()
            try removeCapability(for: next.sessions[index])
            next.sessions[index].protectedCapability = nil
            changed += 1
        }
        guard changed > 0 else { return 0 }
        next.updatedAt = clock.now()
        next = try next.canonicalSorted()
        try publishEnvelope(
            next,
            operation: .cloneOrFork,
            operationID: operationID,
            namespace: nil,
            sessionID: nil
        )
        envelope = next
        return changed
    }

    func markClonedOrForked(
        operationID: UUID = UUID(),
        resultGenerationID: UUID = UUID()
    ) throws -> PortableExchangeCloneForkReceiptV2 {
        try ensureLoaded()
        let sourceGenerationID = envelope?.generationID ?? UUID()
        var next = try envelope ?? emptyEnvelope()
        var invalidated = 0
        for index in next.sessions.indices {
            guard next.sessions[index].capabilityState.isActive,
                  next.sessions[index].protectedCapability != nil else { continue }
            invalidated += 1
            next.sessions[index].state = .historyOnlyClonedOrForked
            next.sessions[index].capabilityState = .historyOnlyClonedOrForked
            next.sessions[index].pendingMutationID = nil
            next.sessions[index].pendingEffectSHA256 = nil
            next.sessions[index].pendingImportReceiptSHA256 = nil
            next.sessions[index].cloneOrForkGenerationID = resultGenerationID
            next.sessions[index].updatedAt = clock.now()
            try removeCapability(for: next.sessions[index])
            next.sessions[index].protectedCapability = nil
        }
        next = try PortableExchangeSessionEnvelopeV2(
            generationID: resultGenerationID,
            updatedAt: clock.now(),
            sessions: next.sessions,
            quarantine: next.quarantine
        )
        try publishEnvelope(
            next,
            operation: .cloneOrFork,
            operationID: operationID,
            namespace: nil,
            sessionID: nil
        )
        envelope = next
        let receipt = try PortableExchangeCloneForkReceiptV2(
            operationID: operationID,
            sourceGenerationID: sourceGenerationID,
            resultGenerationID: resultGenerationID,
            invalidatedSessionCount: invalidated,
            preservedHistoryCount: next.sessions.count,
            completedAt: clock.now()
        )
        return receipt
    }

    func deleteUnfinalizedSubject(
        sessionID: UUID,
        tombstoneProven: Bool,
        operationID: UUID = UUID()
    ) throws -> Bool {
        try ensureLoaded()
        guard tombstoneProven else {
            throw PortableExchangePersistenceFailureV2.invalidTransition
        }
        guard let current = envelope?.sessions.first(where: { $0.sessionID == sessionID }) else {
            return false
        }
        guard current.state.isDiscardableScratch,
              current.responseIDs.isEmpty,
              current.acceptedResponseSHA256 == nil else {
            // Finalized, superseded, cancelled/Unable-equivalent, or other
            // terminal evidence remains append-only history and is never
            // removed by subject cleanup.
            return false
        }
        try removeSessionFiles(current)
        var next = try envelope ?? emptyEnvelope()
        next.sessions.removeAll { $0.sessionID == sessionID }
        try publishEnvelope(
            try next.canonicalSorted(),
            operation: .purge,
            operationID: operationID,
            namespace: current.namespace,
            sessionID: sessionID
        )
        envelope = try next.canonicalSorted()
        return true
    }

    @discardableResult
    func purgeExpired(
        before cutoff: Date,
        operationID: UUID = UUID()
    ) throws -> Int {
        try ensureLoaded()
        var next = try envelope ?? emptyEnvelope()
        let discardable = next.sessions.filter {
            $0.state.isDiscardableScratch &&
                $0.updatedAt < cutoff &&
                $0.responseIDs.isEmpty &&
                $0.acceptedResponseSHA256 == nil
        }
        for record in discardable { try removeSessionFiles(record) }
        let oldQuarantine = next.quarantine.filter {
            $0.createdAt < cutoff &&
                ($0.disposition == .pending || $0.disposition == .keptQuarantined)
        }
        for entry in oldQuarantine { try removeRelativeFile(entry.relativePath, kind: .portableExchangeQuarantineFile) }
        next.sessions.removeAll { record in discardable.contains(where: { $0.sessionID == record.sessionID }) }
        next.quarantine.removeAll { entry in oldQuarantine.contains(where: { $0.quarantineID == entry.quarantineID }) }
        guard !discardable.isEmpty || !oldQuarantine.isEmpty else { return 0 }
        next.updatedAt = clock.now()
        try publishEnvelope(
            try next.canonicalSorted(),
            operation: .purge,
            operationID: operationID,
            namespace: nil,
            sessionID: nil
        )
        envelope = try next.canonicalSorted()
        return discardable.count + oldQuarantine.count
    }

    func erase(
        operationID: UUID = UUID()
    ) throws -> PortableExchangeEraseReceiptV2 {
        try ensureLoaded()
        let current = try envelope ?? emptyEnvelope()
        let sessionCount = current.sessions.count
        let quarantineCount = current.quarantine.count
        let capabilityCount = current.sessions.filter { $0.protectedCapability != nil }.count
        let escapedCopies = current.sessions.filter { $0.escapedCopyAcknowledged }.count
        let removedBytes = current.sessions.reduce(UInt64(0)) {
            $0 + $1.immutableBytes.reduce(UInt64(0)) { $0 + $1.byteCount }
        }
        let empty = try PortableExchangeSessionEnvelopeV2(
            generationID: idSource.makeID(),
            updatedAt: clock.now(),
            sessions: [],
            quarantine: []
        )
        try publishEnvelope(
            empty,
            operation: .erase,
            operationID: operationID,
            namespace: nil,
            sessionID: nil
        )
        for record in current.sessions { try removeSessionFiles(record) }
        for entry in current.quarantine {
            try removeRelativeFile(entry.relativePath, kind: .portableExchangeQuarantineFile)
        }
        envelope = empty
        let receipt = try PortableExchangeEraseReceiptV2(
            operationID: operationID,
            erasedSessionCount: sessionCount,
            erasedQuarantineCount: quarantineCount,
            erasedCapabilityCount: capabilityCount,
            escapedCopiesAcknowledged: escapedCopies,
            appOwnedBytesRemoved: removedBytes,
            completedAt: clock.now()
        )
        return receipt
    }

    // MARK: - Recovery and diagnostics

    func recover() throws {
        loaded = false
        envelope = nil
        try ensureLoaded()
    }

    func migrationReceipt() throws -> PortableExchangeSessionMigrationReceiptV2? {
        try ensureLayout()
        if let lastMigrationReceipt { return lastMigrationReceipt }
        guard fileManager.fileExists(atPath: migrationReceiptURL.path) else { return nil }
        do {
            let data = try readFile(
                migrationReceiptURL,
                kind: .portableExchangeSessionFile,
                maximumByteCount: 64 * 1_024
            )
            let receipt = try StoreMigrationCanonicalJSONV1.decodeCanonical(
                PortableExchangeSessionMigrationReceiptV2.self,
                from: data
            )
            lastMigrationReceipt = receipt
            return receipt
        } catch {
            throw Self.map(error)
        }
    }

    func statistics(
        for namespace: PortableExchangeSessionNamespaceV2
    ) throws -> PortableExchangeSessionStoreStatisticsV2 {
        try ensureLoaded()
        let values = (envelope?.sessions ?? []).filter { $0.namespace == namespace }
        return PortableExchangeSessionStoreStatisticsV2(
            namespace: namespace,
            sessionCount: values.count,
            immutableByteCount: values.reduce(UInt64(0)) {
                $0 + $1.immutableBytes.reduce(UInt64(0)) { $0 + $1.byteCount }
            },
            quarantineByteCount: (envelope?.quarantine ?? [])
                .filter { $0.namespace == namespace }
                .reduce(UInt64(0)) { $0 + $1.byteCount },
            activeCapabilityCount: values.filter { $0.capabilityState.isActive }.count
        )
    }

    // MARK: - Load and migration

    private func ensureLoaded() throws {
        guard !loaded else { return }
        try ensureLayout()
        try recoverPendingJournal()
        if !fileManager.fileExists(atPath: envelopeURL.path) {
            envelope = try emptyEnvelope()
            loaded = true
            return
        }
        let sourceData: Data
        do {
            sourceData = try readFile(
                envelopeURL,
                kind: .portableExchangeSessionFile,
                maximumByteCount: C48PortableReviewPersistenceLimitsV1.maximumEnvelopeBytes
            )
        } catch {
            throw Self.map(error)
        }
        do {
            let version = try Self.storeVersion(in: sourceData)
            switch version {
            case 1:
                let old = try StoreMigrationCanonicalJSONV1.decodeCanonical(
                    PortableExchangeSessionEnvelopeV1.self,
                    from: sourceData
                )
                let migrated = try PortableExchangeSessionEnvelopeV2(
                    generationID: old.generationID,
                    updatedAt: old.updatedAt,
                    sessions: old.sessions,
                    quarantine: old.quarantine
                ).canonicalSorted()
                let resultData = try canonicalData(migrated)
                let receipt = try PortableExchangeSessionMigrationReceiptV2(
                    sourceSHA256: StoreMigrationCanonicalJSONV1.sha256(sourceData),
                    resultSHA256: StoreMigrationCanonicalJSONV1.sha256(resultData),
                    preservedSessionCount: migrated.sessions.count,
                    preservedImmutableByteCount: migrated.sessions.reduce(UInt64(0)) {
                        $0 + $1.immutableBytes.reduce(UInt64(0)) { $0 + $1.byteCount }
                    }
                )
                try publishEnvelope(
                    migrated,
                    operation: .migrate,
                    operationID: idSource.makeID(),
                    namespace: nil,
                    sessionID: nil
                )
                try writeMigrationReceipt(receipt)
                envelope = migrated
                lastMigrationReceipt = receipt
            case 2:
                envelope = try StoreMigrationCanonicalJSONV1.decodeCanonical(
                    PortableExchangeSessionEnvelopeV2.self,
                    from: sourceData
                ).canonicalSorted()
            default:
                throw PortableExchangePersistenceFailureV2.unsupportedSchemaVersion
            }
            loaded = true
        } catch let failure as PortableExchangePersistenceFailureV2 {
            throw failure
        } catch {
            throw PortableExchangePersistenceFailureV2.corruptStore
        }
    }

    private func ensureLayout() throws {
        do {
            try ensureDirectory(rootURL)
            try ensureDirectory(payloadRootURL)
            try ensureDirectory(capabilityRootURL)
            try ensureDirectory(quarantineRootURL)
            try PortableExchangeProtectedFilePolicyV2.validate()
        } catch {
            throw Self.map(error)
        }
    }

    private func emptyEnvelope() throws -> PortableExchangeSessionEnvelopeV2 {
        try PortableExchangeSessionEnvelopeV2(
            generationID: idSource.makeID(),
            updatedAt: clock.now(),
            sessions: [],
            quarantine: []
        )
    }

    private func recoverPendingJournal() throws {
        guard fileManager.fileExists(atPath: journalURL.path) else { return }
        let data = try readFile(
            journalURL,
            kind: .portableExchangeJournalFile,
            maximumByteCount: 64 * 1_024
        )
        let journal: PortableExchangeJournalEntryV2
        do {
            journal = try StoreMigrationCanonicalJSONV1.decodeCanonical(
                PortableExchangeJournalEntryV2.self,
                from: data
            )
        } catch {
            throw PortableExchangePersistenceFailureV2.invalidJournal
        }
        let currentData = fileManager.fileExists(atPath: envelopeURL.path)
            ? (try? readFile(
                envelopeURL,
                kind: .portableExchangeSessionFile,
                maximumByteCount: C48PortableReviewPersistenceLimitsV1.maximumEnvelopeBytes
            ))
            : nil
        let currentDigest = StoreMigrationCanonicalJSONV1.sha256(currentData ?? Data())
        guard currentDigest == journal.beforeSHA256 || currentDigest == journal.afterSHA256 else {
            throw PortableExchangePersistenceFailureV2.corruptStore
        }
        // Both PREPARED and COMMITTED are resolved by the exact digest.  A
        // matching after-image is already complete; a matching before-image
        // never published and is safely rolled back by removing the journal.
        try removeJournal()
    }

    // MARK: - Canonical mutations

    private func appendAndPublish(
        _ record: PortableExchangeSessionRecordV2,
        operation: PortableExchangeJournalOperationV2
    ) throws {
        var next = try envelope ?? emptyEnvelope()
        next.sessions.append(record)
        next.updatedAt = clock.now()
        next = try next.canonicalSorted()
        try publishEnvelope(
            next,
            operation: operation,
            operationID: idSource.makeID(),
            namespace: record.namespace,
            sessionID: record.sessionID
        )
        envelope = next
    }

    private func replaceRecordAndPublish(
        _ record: PortableExchangeSessionRecordV2,
        operation: PortableExchangeJournalOperationV2
    ) throws {
        var next = try envelope ?? emptyEnvelope()
        guard let index = next.sessions.firstIndex(where: { $0.sessionID == record.sessionID }) else {
            throw PortableExchangePersistenceFailureV2.sessionNotFound
        }
        next.sessions[index] = try record.validated()
        next.updatedAt = clock.now()
        next = try next.canonicalSorted()
        try publishEnvelope(
            next,
            operation: operation,
            operationID: idSource.makeID(),
            namespace: record.namespace,
            sessionID: record.sessionID
        )
        envelope = next
    }

    private func publishEnvelope(
        _ candidate: PortableExchangeSessionEnvelopeV2,
        operation: PortableExchangeJournalOperationV2,
        operationID: UUID,
        namespace: PortableExchangeSessionNamespaceV2?,
        sessionID: UUID?
    ) throws {
        let validated = try candidate.canonicalSorted().validated()
        let afterData = try canonicalData(validated)
        guard afterData.count <= C48PortableReviewPersistenceLimitsV1.maximumEnvelopeBytes else {
            throw PortableExchangePersistenceFailureV2.quotaExceeded
        }
        let beforeData = fileManager.fileExists(atPath: envelopeURL.path)
            ? (try readFile(
                envelopeURL,
                kind: .portableExchangeSessionFile,
                maximumByteCount: C48PortableReviewPersistenceLimitsV1.maximumEnvelopeBytes
            ))
            : Data()
        let journal = try PortableExchangeJournalEntryV2(
            operationID: operationID,
            operation: operation,
            namespace: namespace,
            sessionID: sessionID,
            beforeSHA256: StoreMigrationCanonicalJSONV1.sha256(beforeData),
            afterSHA256: StoreMigrationCanonicalJSONV1.sha256(afterData),
            phase: .prepared,
            createdAt: clock.now()
        )
        do {
            try writeJournal(journal)
            try writeAtomically(
                afterData,
                to: envelopeURL,
                kind: .portableExchangeSessionFile
            )
            let committed = try PortableExchangeJournalEntryV2(
                operationID: operationID,
                operation: operation,
                namespace: namespace,
                sessionID: sessionID,
                beforeSHA256: journal.beforeSHA256,
                afterSHA256: journal.afterSHA256,
                phase: .committed,
                createdAt: journal.createdAt
            )
            try writeJournal(committed)
            try removeJournal()
        } catch {
            loaded = false
            envelope = nil
            throw Self.map(error)
        }
    }

    // MARK: - Bytes and quarantine

    private func persistImmutableBytes(
        _ bytes: Data,
        role: PortableExchangeImmutableByteRoleV2,
        sessionID: UUID
    ) throws -> PortableExchangeImmutableByteReferenceV2 {
        guard !bytes.isEmpty,
              UInt64(bytes.count) <= C48PortableReviewPersistenceLimitsV1.maximumImmutableBytes else {
            throw PortableExchangePersistenceFailureV2.invalidPayload
        }
        let digest = StoreMigrationCanonicalJSONV1.sha256(bytes)
        let sessionComponent = sessionID.uuidString.lowercased()
        let roleComponent = role.rawValue.lowercased()
        let relativePath = "\(PortableExchangeSessionStoreLayoutV2.payloadDirectoryName)/\(sessionComponent)/\(roleComponent)-\(digest).bin"
        let sessionURL = payloadRootURL.appendingPathComponent(sessionComponent, isDirectory: true)
        try ensureDirectory(sessionURL)
        let url = rootURL.appendingPathComponent(relativePath, isDirectory: false)
        if fileManager.fileExists(atPath: url.path) {
            let existing = try readFile(
                url,
                kind: .portableExchangeSessionFile,
                maximumByteCount: C48PortableReviewPersistenceLimitsV1.maximumImmutableBytes
            )
            guard existing == bytes else { throw PortableExchangePersistenceFailureV2.corruptStore }
        } else {
            try writeAtomically(bytes, to: url, kind: .portableExchangeSessionFile)
        }
        return try PortableExchangeImmutableByteReferenceV2(
            role: role,
            sha256: digest,
            byteCount: UInt64(bytes.count),
            relativePath: relativePath,
            released: role != .acceptedResponse
        )
    }

    private func persistCapability(
        _ capability: BearerResponseCapabilityV1,
        sessionID: UUID,
        state: PortableExchangeCapabilityStateV2
    ) throws -> PortableExchangeProtectedCapabilityArtifactV2 {
        try PortableReviewLimitsV1.capability(capability.rawBytes)
        let relativePath = "\(PortableExchangeSessionStoreLayoutV2.capabilityDirectoryName)/\(sessionID.uuidString.lowercased()).bin"
        try ensureDirectory(capabilityRootURL)
        let url = rootURL.appendingPathComponent(relativePath, isDirectory: false)
        if fileManager.fileExists(atPath: url.path) {
            let existing = try readCapability(relativePath)
            guard existing == capability.rawBytes else {
                throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
            }
        } else {
            try writeAtomically(
                capability.rawBytes,
                to: url,
                kind: .portableExchangeSessionFile
            )
        }
        return try PortableExchangeProtectedCapabilityArtifactV2(
            relativePath: relativePath,
            byteCount: UInt64(capability.rawBytes.count),
            sha256: StoreMigrationCanonicalJSONV1.sha256(capability.rawBytes),
            state: state
        )
    }

    private func quarantine(
        _ bytes: Data,
        namespace: PortableExchangeSessionNamespaceV2,
        reason: String
    ) throws {
        try ensureLoaded()
        guard !bytes.isEmpty,
              UInt64(bytes.count) <= C48PortableReviewPersistenceLimitsV1.maximumImmutableBytes else {
            throw PortableExchangePersistenceFailureV2.invalidPayload
        }
        let quarantineID = idSource.makeID()
        let relativePath = "\(PortableExchangeSessionStoreLayoutV2.quarantineDirectoryName)/\(quarantineID.uuidString.lowercased()).bin"
        let url = rootURL.appendingPathComponent(relativePath, isDirectory: false)
        try writeAtomically(bytes, to: url, kind: .portableExchangeQuarantineFile)
        let entry = try PortableExchangeQuarantineRecordV2(
            quarantineID: quarantineID,
            namespace: namespace,
            relativePath: relativePath,
            sha256: StoreMigrationCanonicalJSONV1.sha256(bytes),
            byteCount: UInt64(bytes.count),
            reason: reason,
            createdAt: clock.now()
        )
        var next = try envelope ?? emptyEnvelope()
        next.quarantine.append(entry)
        next.updatedAt = clock.now()
        try publishEnvelope(
            try next.canonicalSorted(),
            operation: .stage,
            operationID: idSource.makeID(),
            namespace: namespace,
            sessionID: nil
        )
        envelope = try next.canonicalSorted()
    }

    private func readPayload(_ relativePath: String) throws -> Data {
        guard relativePath.hasPrefix("\(PortableExchangeSessionStoreLayoutV2.payloadDirectoryName)/") else {
            throw PortableExchangePersistenceFailureV2.invalidRecord
        }
        let url = try safeURL(relativePath)
        return try readFile(
            url,
            kind: .portableExchangeSessionFile,
            maximumByteCount: C48PortableReviewPersistenceLimitsV1.maximumImmutableBytes
        )
    }

    private func readCapability(_ relativePath: String) throws -> Data {
        guard relativePath.hasPrefix("\(PortableExchangeSessionStoreLayoutV2.capabilityDirectoryName)/") else {
            throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
        }
        let url = try safeURL(relativePath)
        let data = try readFile(
            url,
            kind: .portableExchangeSessionFile,
            maximumByteCount: PortableReviewLimitsV1.capabilityByteCount
        )
        guard data.count == PortableReviewLimitsV1.capabilityByteCount else {
            throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
        }
        return data
    }

    private func removeSessionFiles(_ record: PortableExchangeSessionRecordV2) throws {
        for reference in record.immutableBytes {
            try removeRelativeFile(reference.relativePath, kind: .portableExchangeSessionFile)
        }
        if let capability = record.protectedCapability {
            try removeRelativeFile(capability.relativePath, kind: .portableExchangeSessionFile)
        }
        let payloadSessionURL = payloadRootURL.appendingPathComponent(
            record.sessionID.uuidString.lowercased(),
            isDirectory: true
        )
        if fileManager.fileExists(atPath: payloadSessionURL.path) {
            try fileManager.removeItem(at: payloadSessionURL)
        }
    }

    private func removeCapability(for record: PortableExchangeSessionRecordV2) throws {
        guard let capability = record.protectedCapability else { return }
        try removeRelativeFile(capability.relativePath, kind: .portableExchangeSessionFile)
    }

    // MARK: - Restore and validation helpers

    private func restoredEnvelope(
        from snapshot: PortableExchangeBackupSnapshotV2
    ) throws -> PortableExchangeSessionEnvelopeV2 {
        var restoredSessions: [PortableExchangeSessionRecordV2] = []
        let payloadMap = Dictionary(uniqueKeysWithValues: snapshot.immutablePayloads.map {
            ("\($0.role.rawValue):\($0.sha256)", $0.bytes)
        })
        let capabilityMap = Dictionary(uniqueKeysWithValues: snapshot.protectedCapabilityArtifacts.map {
            ($0.sessionID, $0)
        })
        for source in snapshot.sessions {
            var refs: [PortableExchangeImmutableByteReferenceV2] = []
            for reference in source.immutableBytes {
                let key = "\(reference.role.rawValue):\(reference.sha256)"
                guard let bytes = payloadMap[key],
                      StoreMigrationCanonicalJSONV1.sha256(bytes) == reference.sha256,
                      UInt64(bytes.count) == reference.byteCount else {
                    throw PortableExchangePersistenceFailureV2.invalidBackupSnapshot
                }
                refs.append(try persistImmutableBytes(
                    bytes,
                    role: reference.role,
                    sessionID: source.sessionID
                ))
            }
            var artifact: PortableExchangeProtectedCapabilityArtifactV2?
            if let sourceArtifact = source.protectedCapability {
                guard let backup = capabilityMap[source.sessionID],
                      backup.state.isActive else {
                    throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
                }
                let capability = try BearerResponseCapabilityV1(rawBytes: backup.bytes)
                artifact = try persistCapability(
                    capability,
                    sessionID: source.sessionID,
                    state: source.capabilityState
                )
                guard artifact?.sha256 == sourceArtifact.sha256 else {
                    throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
                }
            }
            restoredSessions.append(try PortableExchangeSessionRecordV2(
                sessionID: source.sessionID,
                namespace: source.namespace,
                publicRequestID: source.publicRequestID,
                revision: source.revision,
                workspaceID: source.workspaceID,
                canonicalReviewIdentity: source.canonicalReviewIdentity,
                canonicalSubjectIdentity: source.canonicalSubjectIdentity,
                protocolReleaseDigest: source.protocolReleaseDigest,
                pendingMutationID: source.pendingMutationID,
                pendingEffectSHA256: source.pendingEffectSHA256,
                pendingImportReceiptSHA256: source.pendingImportReceiptSHA256,
                createdAt: source.createdAt,
                updatedAt: source.updatedAt,
                state: source.state,
                capabilityState: source.capabilityState,
                attemptCount: source.attemptCount,
                immutableBytes: refs,
                protectedCapability: artifact,
                responseIDs: source.responseIDs,
                requestManifestSHA256: source.requestManifestSHA256,
                requestPackageSHA256: source.requestPackageSHA256,
                acceptedResponseSHA256: source.acceptedResponseSHA256,
                cloneOrForkGenerationID: source.cloneOrForkGenerationID,
                escapedCopyAcknowledged: source.escapedCopyAcknowledged
            ))
        }
        return try PortableExchangeSessionEnvelopeV2(
            generationID: idSource.makeID(),
            updatedAt: clock.now(),
            sessions: restoredSessions,
            quarantine: []
        ).canonicalSorted()
    }

    private func validateStageInput(
        _ input: PortableExchangeSessionStageInputV2
    ) throws {
        guard input.revision > 0,
              C48PortableReviewPersistenceValidationV1.validPublicID(input.publicRequestID),
              input.state != .erased,
              input.state != .historyOnlyTerminal,
              input.state != .historyOnlySuperseded,
              input.state != .historyOnlyClonedOrForked else {
            throw PortableExchangePersistenceFailureV2.invalidRecord
        }
        if let manifest = input.requestManifestBytes {
            guard !manifest.isEmpty,
                  UInt64(manifest.count) <= C48PortableReviewPersistenceLimitsV1.maximumImmutableBytes else {
                throw PortableExchangePersistenceFailureV2.invalidPayload
            }
        }
        if let package = input.requestPackageBytes {
            guard !package.isEmpty,
                  UInt64(package.count) <= C48PortableReviewPersistenceLimitsV1.maximumImmutableBytes else {
                throw PortableExchangePersistenceFailureV2.invalidPayload
            }
        }
        if let capability = input.capability {
            try PortableReviewLimitsV1.capability(capability.rawBytes)
        } else if input.state == .exportedAwaitingResponse || input.state == .responsePendingDecision {
            throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
        }
        if let protocolReleaseDigest = input.protocolReleaseDigest {
            guard protocolReleaseDigest.count == PortableReviewLimitsV1.digestByteCount else {
                throw PortableExchangePersistenceFailureV2.invalidRecord
            }
        }
    }

    private func requireSession(
        for requestID: ReviewRequestPublicIDV1
    ) throws -> UUID {
        guard let session = envelope?.sessions.first(where: {
            $0.namespace == .review &&
                $0.publicRequestID == requestID.rawValue
        }) else {
            throw PortableExchangePersistenceFailureV2.sessionNotFound
        }
        return session.sessionID
    }

    private func capabilityState(
        for state: PortableExchangeSessionStateV2
    ) -> PortableExchangeCapabilityStateV2 {
        switch state {
        case .openUnexported: return .issuedNotExported
        case .exportedAwaitingResponse: return .exportedAccepting
        case .responsePendingDecision, .acknowledgedAwaitingDecision: return .responsePendingDecision
        case .approvalResponseRecorded,
             .changesResponseRecorded,
             .historyOnlyTerminal: return .historyOnlyTerminal
        case .superseded, .historyOnlySuperseded: return .historyOnlySuperseded
        case .closedWithoutResponse: return .historyOnlyTerminal
        case .historyOnlyClonedOrForked: return .historyOnlyClonedOrForked
        case .quarantined: return .unavailableCorruptOrMissing
        case .erasePending: return .erasePending
        case .erased: return .erased
        }
    }

    private func state(
        for disposition: ReviewResponseDispositionV1
    ) -> PortableExchangeSessionStateV2 {
        switch disposition {
        case .acknowledged: return .acknowledgedAwaitingDecision
        case .approved: return .approvalResponseRecorded
        case .changesRequested: return .changesResponseRecorded
        }
    }

    private func lifecycleState(
        for state: PortableExchangeCapabilityStateV2
    ) -> PortableReviewLifecycleStateV1 {
        switch state {
        case .issuedNotExported: return .issuedNotExported
        case .exportedAccepting: return .exportedAccepting
        case .responsePendingDecision: return .responsePendingDecision
        case .historyOnlyTerminal: return .historyOnlyTerminal
        case .historyOnlySuperseded: return .historyOnlySuperseded
        case .historyOnlyClonedOrForked: return .historyOnlyClonedOrForked
        case .unavailableCorruptOrMissing: return .unavailableCorruptOrMissing
        case .erasePending: return .erasePending
        case .erased: return .erased
        }
    }

    private static func sessionOrder(
        _ lhs: PortableExchangeSessionRecordV2,
        _ rhs: PortableExchangeSessionRecordV2
    ) -> Bool {
        (
            lhs.namespace.rawValue,
            lhs.publicRequestID,
            lhs.revision,
            lhs.sessionID.uuidString
        ) < (
            rhs.namespace.rawValue,
            rhs.publicRequestID,
            rhs.revision,
            rhs.sessionID.uuidString
        )
    }

    private static func storeVersion(in data: Data) throws -> Int {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw PortableExchangePersistenceFailureV2.corruptStore
        }
        if let value = dictionary["schemaVersion"] as? Int { return value }
        if let value = dictionary["storeVersion"] as? Int { return value }
        throw PortableExchangePersistenceFailureV2.corruptStore
    }

    private nonisolated static func staticStoreVersion(in data: Data) throws -> Int {
        try storeVersion(in: data)
    }

    private nonisolated static func staticSafeURL(
        _ relativePath: String,
        rootURL: URL
    ) throws -> URL {
        guard C48PortableReviewPersistenceValidationV1.validRelativePath(relativePath) else {
            throw PortableExchangePersistenceFailureV2.invalidRecord
        }
        let rootPath = rootURL.standardizedFileURL.path
        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            throw PortableExchangePersistenceFailureV2.invalidRecord
        }
        return candidate
    }

    private nonisolated static func staticRead(
        _ url: URL,
        kind: OwnedFileKindV1,
        maximumByteCount: UInt64
    ) throws -> Data {
        do {
            try ProtectedFilePolicyV1.verify(kind, at: url)
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard UInt64(data.count) <= maximumByteCount else {
                throw PortableExchangePersistenceFailureV2.quotaExceeded
            }
            return data
        } catch let failure as PortableExchangePersistenceFailureV2 {
            throw failure
        } catch {
            throw Self.map(error)
        }
    }

    private nonisolated static func staticEnsureDirectory(
        _ url: URL,
        fileManager: FileManager,
        intermediate: Bool = false
    ) throws {
        do {
            if !fileManager.fileExists(atPath: url.path) {
                try fileManager.createDirectory(
                    at: url,
                    withIntermediateDirectories: intermediate
                )
            }
            try ProtectedFilePolicyV1.applyAndVerify(
                .portableExchangeDirectory,
                at: url
            )
        } catch {
            throw Self.map(error)
        }
    }

    private nonisolated static func staticDecodeEnvelope(
        _ data: Data
    ) throws -> PortableExchangeSessionEnvelopeV2 {
        do {
            let version = try staticStoreVersion(in: data)
            switch version {
            case 1:
                let old = try StoreMigrationCanonicalJSONV1.decodeCanonical(
                    PortableExchangeSessionEnvelopeV1.self,
                    from: data
                )
                return try PortableExchangeSessionEnvelopeV2(
                    generationID: old.generationID,
                    updatedAt: old.updatedAt,
                    sessions: old.sessions,
                    quarantine: old.quarantine
                ).canonicalSorted()
            case 2:
                return try StoreMigrationCanonicalJSONV1.decodeCanonical(
                    PortableExchangeSessionEnvelopeV2.self,
                    from: data
                ).canonicalSorted()
            default:
                throw PortableExchangePersistenceFailureV2.unsupportedSchemaVersion
            }
        } catch let failure as PortableExchangePersistenceFailureV2 {
            throw failure
        } catch {
            throw PortableExchangePersistenceFailureV2.corruptStore
        }
    }

    private nonisolated static func staticPayloadMap(
        _ payloads: [PortableExchangeImmutablePayloadV2]
    ) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for payload in payloads {
            try payload.validate()
            let key = "\(payload.role.rawValue):\(payload.sha256)"
            guard result.updateValue(payload.bytes, forKey: key) == nil else {
                throw PortableExchangePersistenceFailureV2.invalidBackupSnapshot
            }
        }
        return result
    }

    private nonisolated static func staticCapabilityMap(
        _ artifacts: [PortableExchangeProtectedCapabilityBackupV2]
    ) throws -> [UUID: PortableExchangeProtectedCapabilityBackupV2] {
        var result: [UUID: PortableExchangeProtectedCapabilityBackupV2] = [:]
        for artifact in artifacts {
            try artifact.validate()
            guard result.updateValue(artifact, forKey: artifact.sessionID) == nil else {
                throw PortableExchangePersistenceFailureV2.invalidBackupSnapshot
            }
        }
        return result
    }

    private nonisolated static func staticValidateCanonicalCapabilityInventory(
        capabilityRootURL: URL,
        expectedBytesByPath: [String: Data],
        ignoredRecoveryStagePaths: Set<String>,
        fileManager: FileManager
    ) throws {
        var actualPaths = Set<String>()
        for candidate in try fileManager.contentsOfDirectory(
            at: capabilityRootURL,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            let path = candidate.standardizedFileURL.path
            if ignoredRecoveryStagePaths.contains(path) {
                guard !candidate.hasDirectoryPath else {
                    throw PortableExchangePersistenceFailureV2.corruptStore
                }
                continue
            }
            guard !candidate.hasDirectoryPath,
                  let expected = expectedBytesByPath[path] else {
                throw PortableExchangePersistenceFailureV2.corruptStore
            }
            let actual = try staticRead(
                candidate,
                kind: .portableExchangeSessionFile,
                maximumByteCount: PortableReviewLimitsV1.capabilityByteCount
            )
            guard actual == expected,
                  actualPaths.insert(path).inserted else {
                throw PortableExchangePersistenceFailureV2.corruptStore
            }
        }
        guard actualPaths == Set(expectedBytesByPath.keys) else {
            throw PortableExchangePersistenceFailureV2.corruptStore
        }
    }

    private nonisolated static func staticRecoveryOldStageURL(
        capabilityRootURL: URL,
        operationID: UUID,
        sessionID: UUID,
        fileManager: FileManager
    ) throws -> URL? {
        try staticRecoveryOldStageURLs(
            capabilityRootURL: capabilityRootURL,
            operationID: operationID,
            fileManager: fileManager
        )[sessionID]
    }

    private nonisolated static func staticRecoveryOldStageURLs(
        capabilityRootURL: URL,
        operationID: UUID,
        fileManager: FileManager
    ) throws -> [UUID: URL] {
        let prefix = ".recovery-old-\(operationID.uuidString.lowercased())-"
        var result: [UUID: URL] = [:]
        for candidate in try fileManager.contentsOfDirectory(
            at: capabilityRootURL,
            includingPropertiesForKeys: nil,
            options: []
        ) where candidate.lastPathComponent.hasPrefix(prefix) {
            let name = candidate.lastPathComponent
            guard name.hasSuffix(".bin") else {
                throw PortableExchangePersistenceFailureV2.corruptStore
            }
            let body = String(name.dropFirst(prefix.count).dropLast(4))
            guard body.count > 37 else {
                throw PortableExchangePersistenceFailureV2.corruptStore
            }
            let sessionEnd = body.index(body.startIndex, offsetBy: 36)
            guard body[sessionEnd] == "-" else {
                throw PortableExchangePersistenceFailureV2.corruptStore
            }
            let sessionID = UUID(uuidString: String(body[..<sessionEnd]))
            let digest = String(body[body.index(after: sessionEnd)...])
            guard let sessionID,
                  StoreMigrationCanonicalJSONV1.isLowercaseSHA256(digest),
                  result.updateValue(candidate, forKey: sessionID) == nil else {
                throw PortableExchangePersistenceFailureV2.corruptStore
            }
        }
        return result
    }

    private nonisolated static func staticRecoverySessions(
        _ sourceSessions: [PortableExchangeSessionRecordV2],
        capabilities: [UUID: PortableExchangeProtectedCapabilityBackupV2],
        expectedResultGenerationID: UUID,
        cloneOrFork: Bool
    ) throws -> [PortableExchangeSessionRecordV2] {
        try sourceSessions.map { source in
            var state = source.state
            var capabilityState = source.capabilityState
            var pendingMutationID = source.pendingMutationID
            var pendingEffectSHA256 = source.pendingEffectSHA256
            var pendingImportReceiptSHA256 = source.pendingImportReceiptSHA256
            var cloneGenerationID = source.cloneOrForkGenerationID
            var protectedCapability = source.protectedCapability
            if cloneOrFork,
               source.protectedCapability != nil,
               source.capabilityState.isActive {
                state = .historyOnlyClonedOrForked
                capabilityState = .historyOnlyClonedOrForked
                pendingMutationID = nil
                pendingEffectSHA256 = nil
                pendingImportReceiptSHA256 = nil
                cloneGenerationID = expectedResultGenerationID
                protectedCapability = nil
            }
            if let artifact = source.protectedCapability {
                guard let backup = capabilities[source.sessionID],
                      backup.state == source.capabilityState,
                      backup.bytes.count == PortableReviewLimitsV1.capabilityByteCount,
                      StoreMigrationCanonicalJSONV1.sha256(backup.bytes) == artifact.sha256 else {
                    throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
                }
            } else if source.capabilityState == .exportedAccepting ||
                      source.capabilityState == .responsePendingDecision {
                throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
            }
            return try PortableExchangeSessionRecordV2(
                sessionID: source.sessionID,
                namespace: source.namespace,
                publicRequestID: source.publicRequestID,
                revision: source.revision,
                workspaceID: source.workspaceID,
                canonicalReviewIdentity: source.canonicalReviewIdentity,
                canonicalSubjectIdentity: source.canonicalSubjectIdentity,
                protocolReleaseDigest: source.protocolReleaseDigest,
                pendingMutationID: pendingMutationID,
                pendingEffectSHA256: pendingEffectSHA256,
                pendingImportReceiptSHA256: pendingImportReceiptSHA256,
                createdAt: source.createdAt,
                updatedAt: source.updatedAt,
                state: state,
                capabilityState: capabilityState,
                attemptCount: source.attemptCount,
                immutableBytes: source.immutableBytes,
                protectedCapability: protectedCapability,
                responseIDs: source.responseIDs,
                requestManifestSHA256: source.requestManifestSHA256,
                requestPackageSHA256: source.requestPackageSHA256,
                acceptedResponseSHA256: source.acceptedResponseSHA256,
                cloneOrForkGenerationID: cloneGenerationID,
                escapedCopyAcknowledged: source.escapedCopyAcknowledged
            )
        }
    }

    private nonisolated static func staticWriteAtomically(
        _ data: Data,
        to url: URL,
        kind: OwnedFileKindV1,
        fileManager: FileManager,
        operationID: UUID
    ) throws {
        let parent = url.deletingLastPathComponent()
        do {
            if !fileManager.fileExists(atPath: parent.path) {
                try fileManager.createDirectory(
                    at: parent,
                    withIntermediateDirectories: false
                )
            }
            try ProtectedFilePolicyV1.applyAndVerify(
                .portableExchangeDirectory,
                at: parent
            )
            if fileManager.fileExists(atPath: url.path) {
                let existing = try staticRead(
                    url,
                    kind: kind,
                    maximumByteCount: max(
                        UInt64(data.count),
                        C48PortableReviewPersistenceLimitsV1.maximumEnvelopeBytes
                    )
                )
                guard existing == data else {
                    throw PortableExchangePersistenceFailureV2.corruptStore
                }
                return
            }
            let temporary = parent.appendingPathComponent(
                ".recovery-\(operationID.uuidString.lowercased())-\(UUID().uuidString.lowercased())",
                isDirectory: false
            )
            try data.write(to: temporary, options: [.atomic])
            try ProtectedFilePolicyV1.applyAndVerify(kind, at: temporary)
            try fileManager.moveItem(at: temporary, to: url)
            try ProtectedFilePolicyV1.verify(kind, at: url)
        } catch let failure as PortableExchangePersistenceFailureV2 {
            throw failure
        } catch {
            throw Self.map(error)
        }
    }

    private nonisolated static func staticWriteAndFsyncAtomically(
        _ data: Data,
        to url: URL,
        kind: OwnedFileKindV1,
        fileManager: FileManager,
        operationID: UUID
    ) throws {
        try staticWriteAtomically(
            data,
            to: url,
            kind: kind,
            fileManager: fileManager,
            operationID: operationID
        )
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw PortableExchangePersistenceFailureV2.writeFailed
        }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw PortableExchangePersistenceFailureV2.writeFailed
        }
        let parentDescriptor = Darwin.open(
            url.deletingLastPathComponent().path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard parentDescriptor >= 0 else {
            throw PortableExchangePersistenceFailureV2.writeFailed
        }
        defer { _ = Darwin.close(parentDescriptor) }
        guard Darwin.fsync(parentDescriptor) == 0 else {
            throw PortableExchangePersistenceFailureV2.writeFailed
        }
    }

    /// Replaces an existing protected file only when its bytes are the exact
    /// expected preimage.  The ordinary write helper intentionally rejects a
    /// differing destination, so recovery uses this separate primitive for
    /// the expected-before -> target transition and for journal phase advance.
    private nonisolated static func staticReplaceAtomically(
        _ data: Data,
        to url: URL,
        expectedCurrentData: Data,
        kind: OwnedFileKindV1,
        fileManager: FileManager,
        operationID: UUID
    ) throws {
        let parent = url.deletingLastPathComponent()
        do {
            guard fileManager.fileExists(atPath: url.path) else {
                throw PortableExchangePersistenceFailureV2.corruptStore
            }
            let current = try staticRead(
                url,
                kind: kind,
                maximumByteCount: max(
                    UInt64(expectedCurrentData.count),
                    C48PortableReviewPersistenceLimitsV1.maximumEnvelopeBytes
                )
            )
            guard current == expectedCurrentData else {
                throw PortableExchangePersistenceFailureV2.corruptStore
            }
            try ProtectedFilePolicyV1.applyAndVerify(
                .portableExchangeDirectory,
                at: parent
            )
            let temporary = parent.appendingPathComponent(
                ".recovery-replace-\(operationID.uuidString.lowercased())-\(UUID().uuidString.lowercased())",
                isDirectory: false
            )
            try data.write(to: temporary, options: [.atomic])
            try ProtectedFilePolicyV1.applyAndVerify(kind, at: temporary)
            try fileManager.replaceItemAt(
                url,
                withItemAt: temporary,
                backupItemName: nil,
                options: []
            )
            try ProtectedFilePolicyV1.verify(kind, at: url)
            let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else {
                throw PortableExchangePersistenceFailureV2.writeFailed
            }
            defer { _ = Darwin.close(descriptor) }
            guard Darwin.fsync(descriptor) == 0 else {
                throw PortableExchangePersistenceFailureV2.writeFailed
            }
            let parentDescriptor = Darwin.open(
                parent.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard parentDescriptor >= 0 else {
                throw PortableExchangePersistenceFailureV2.writeFailed
            }
            defer { _ = Darwin.close(parentDescriptor) }
            guard Darwin.fsync(parentDescriptor) == 0 else {
                throw PortableExchangePersistenceFailureV2.writeFailed
            }
            let replaced = try staticRead(
                url,
                kind: kind,
                maximumByteCount: max(
                    UInt64(data.count),
                    C48PortableReviewPersistenceLimitsV1.maximumEnvelopeBytes
                )
            )
            guard replaced == data else {
                throw PortableExchangePersistenceFailureV2.corruptStore
            }
        } catch let failure as PortableExchangePersistenceFailureV2 {
            throw failure
        } catch {
            throw Self.map(error)
        }
    }

    private nonisolated static func staticRemove(
        _ url: URL,
        kind: OwnedFileKindV1,
        fileManager: FileManager
    ) throws {
        do {
            guard fileManager.fileExists(atPath: url.path) else { return }
            try ProtectedFilePolicyV1.verify(kind, at: url)
            try fileManager.removeItem(at: url)
        } catch let failure as PortableExchangePersistenceFailureV2 {
            throw failure
        } catch {
            throw Self.map(error)
        }
    }

    private nonisolated static func staticRemoveIfExact(
        _ url: URL,
        expectedBytes: Data,
        kind: OwnedFileKindV1,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let existing = try staticRead(
            url,
            kind: kind,
            maximumByteCount: max(
                UInt64(expectedBytes.count),
                C48PortableReviewPersistenceLimitsV1.maximumImmutableBytes
            )
        )
        guard existing == expectedBytes else {
            throw PortableExchangePersistenceFailureV2.corruptStore
        }
        try staticRemove(url, kind: kind, fileManager: fileManager)
    }

    private struct PortableExchangeStaticRecoveryCapabilityPlan {
        let sessionID: UUID
        let targetArtifact: PortableExchangeProtectedCapabilityArtifactV2?
        let backup: PortableExchangeProtectedCapabilityBackupV2?
        let targetURL: URL?
        let targetStageURL: URL?
        let oldArtifact: PortableExchangeProtectedCapabilityArtifactV2?
        let oldURL: URL?
        let oldBytes: Data?
        let oldStageURL: URL?
    }

    private static func hexData(_ value: String) -> Data? {
        guard value.utf8.count == 64,
              value.utf8.allSatisfy({
                  ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66)
              }) else { return nil }
        var bytes = Data()
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    private func canonicalData<T: Encodable>(_ value: T) throws -> Data {
        do { return try StoreMigrationCanonicalJSONV1.encode(value) }
        catch { throw PortableExchangePersistenceFailureV2.writeFailed }
    }

    private func canonicalResponseBytes(
        _ response: ReviewResponseEnvelopeV1
    ) throws -> Data {
        do { return try PortableReviewCanonicalCodecV1.responseBytes(response) }
        catch { throw PortableExchangePersistenceFailureV2.invalidPayload }
    }

    // MARK: - Protected file helpers

    private func ensureDirectory(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        }
        try ProtectedFilePolicyV1.applyAndVerify(
            .portableExchangeDirectory,
            at: url
        )
    }

    private func safeURL(_ relativePath: String) throws -> URL {
        guard C48PortableReviewPersistenceValidationV1.validRelativePath(relativePath) else {
            throw PortableExchangePersistenceFailureV2.invalidRecord
        }
        let candidate = rootURL
            .appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            throw PortableExchangePersistenceFailureV2.invalidRecord
        }
        return candidate
    }

    private func readFile(
        _ url: URL,
        kind: OwnedFileKindV1,
        maximumByteCount: UInt64
    ) throws -> Data {
        do {
            try ProtectedFilePolicyV1.verify(kind, at: url)
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard UInt64(data.count) <= maximumByteCount else {
                throw PortableExchangePersistenceFailureV2.quotaExceeded
            }
            return data
        } catch let failure as PortableExchangePersistenceFailureV2 {
            throw failure
        } catch {
            throw Self.map(error)
        }
    }

    private func writeAtomically(
        _ data: Data,
        to url: URL,
        kind: OwnedFileKindV1
    ) throws {
        let parent = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: false)
            try ProtectedFilePolicyV1.applyAndVerify(
                .portableExchangeDirectory,
                at: parent
            )
        }
        let temporary = parent.appendingPathComponent(
            ".tmp-\(idSource.makeID().uuidString.lowercased())",
            isDirectory: false
        )
        do {
            try data.write(to: temporary, options: [.atomic])
            try ProtectedFilePolicyV1.applyAndVerify(kind, at: temporary)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(
                    url,
                    withItemAt: temporary,
                    backupItemName: nil,
                    options: .usingNewMetadataOnly
                )
            } else {
                try fileManager.moveItem(at: temporary, to: url)
            }
            try ProtectedFilePolicyV1.verify(kind, at: url)
        } catch {
            if fileManager.fileExists(atPath: temporary.path) {
                try? fileManager.removeItem(at: temporary)
            }
            throw Self.map(error)
        }
    }

    private func writeJournal(
        _ journal: PortableExchangeJournalEntryV2
    ) throws {
        try writeAtomically(
            try canonicalData(journal),
            to: journalURL,
            kind: .portableExchangeJournalFile
        )
    }

    private func removeJournal() throws {
        guard fileManager.fileExists(atPath: journalURL.path) else { return }
        try ProtectedFilePolicyV1.verify(
            .portableExchangeJournalFile,
            at: journalURL
        )
        try fileManager.removeItem(at: journalURL)
    }

    private func writeMigrationReceipt(
        _ receipt: PortableExchangeSessionMigrationReceiptV2
    ) throws {
        try writeAtomically(
            try canonicalData(receipt),
            to: migrationReceiptURL,
            kind: .portableExchangeSessionFile
        )
    }

    private func removeRelativeFile(
        _ relativePath: String,
        kind: OwnedFileKindV1
    ) throws {
        let url = try safeURL(relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try ProtectedFilePolicyV1.verify(kind, at: url)
        try fileManager.removeItem(at: url)
    }

    private static func map(_ error: Error) -> PortableExchangePersistenceFailureV2 {
        if let failure = error as? PortableExchangePersistenceFailureV2 { return failure }
        if let policy = error as? ProtectedFilePolicyError {
            switch policy {
            case .protectedDataUnavailable: return .protectedDataUnavailable
            case .missing: return .corruptStore
            default: return .writeFailed
            }
        }
        let cocoa = error as NSError
        if cocoa.domain == NSCocoaErrorDomain {
            switch cocoa.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return .protectedDataUnavailable
            case NSFileWriteOutOfSpaceError, NSFileWriteVolumeReadOnlyError:
                return .storageUnavailable
            default: break
            }
        }
        return .writeFailed
    }
}

enum PortableExchangeSessionStoreLayoutV2 {
    static let directoryName = "PortableReviewExchangeV2"
    static let envelopeFileName = "sessions.json"
    static let journalFileName = "sessions.journal.json"
    static let migrationReceiptFileName = "migration-receipt.json"
    static let payloadDirectoryName = "payload"
    static let capabilityDirectoryName = "capability"
    static let quarantineDirectoryName = "quarantine"
}

// MARK: - Existing C14 two-plane reconciliation seam

extension PortableExchangeSessionStoreV2: PortableReviewSessionReconciliationV1 {
    func prepareAcceptAndApply(
        plan: ExternalReviewImportPlanV1,
        receipt: ExternalReviewImportReceiptV1
    ) async throws {
        try plan.validate()
        try receipt.validate()
        guard plan.decision == .acceptAndApply,
              receipt.decision == .acceptAndApply,
              plan.mutationID == receipt.mutationID,
              plan.workspaceID == receipt.workspaceID,
              receipt.responseRecordID == plan.responseRecord.recordID else {
            throw PortableExchangePersistenceFailureV2.invalidTransition
        }
        try ensureLoaded()
        guard var current = envelope?.sessions.first(where: {
            $0.namespace == .review &&
                $0.publicRequestID == plan.requestPublicID.rawValue
        }) else {
            throw PortableExchangePersistenceFailureV2.sessionNotFound
        }
        guard current.workspaceID == nil || current.workspaceID == plan.workspaceID.rawValue else {
            throw PortableExchangePersistenceFailureV2.invalidTransition
        }
        guard current.canonicalSubjectIdentity == nil ||
            current.canonicalSubjectIdentity == plan.c14Mapping.subject.subjectID else {
            throw PortableExchangePersistenceFailureV2.invalidTransition
        }
        current.workspaceID = plan.workspaceID.rawValue
        current.canonicalSubjectIdentity = plan.c14Mapping.subject.subjectID
        current.canonicalReviewIdentity = current.canonicalReviewIdentity ?? plan.requestPublicID.rawValue
        let response = try responseMetadata(
            plan.responseRecord.canonicalResponse.canonicalBytes,
            fallbackResponseID: plan.responseRecord.recordID.uuidString.lowercased()
        )
        let responseDigest = StoreMigrationCanonicalJSONV1.sha256(
            plan.responseRecord.canonicalResponse.canonicalBytes
        )
        let effectDigest = Self.hexString(receipt.effectDigest)
        let importReceiptDigest = try receiptDigest(receipt)
        if let pending = current.pendingMutationID {
            guard pending == plan.mutationID,
                  current.pendingEffectSHA256 == effectDigest,
                  current.pendingImportReceiptSHA256 == importReceiptDigest else {
                throw PortableExchangePersistenceFailureV2.invalidTransition
            }
            return
        }
        if let existing = current.responseIDs.firstIndex(of: response.id) {
            guard current.acceptedResponseSHA256 == responseDigest else {
                throw PortableExchangePersistenceFailureV2.duplicateSession
            }
            current.pendingMutationID = plan.mutationID
            current.pendingEffectSHA256 = effectDigest
            current.pendingImportReceiptSHA256 = importReceiptDigest
        } else {
            let reference = try persistImmutableBytes(
                plan.responseRecord.canonicalResponse.canonicalBytes,
                role: .acceptedResponse,
                sessionID: current.sessionID
            )
            current.immutableBytes.append(reference)
            current.responseIDs.append(response.id)
            current.acceptedResponseSHA256 = responseDigest
            current.pendingMutationID = plan.mutationID
            current.pendingEffectSHA256 = effectDigest
            current.pendingImportReceiptSHA256 = importReceiptDigest
        }
        current.state = .responsePendingDecision
        current.capabilityState = .responsePendingDecision
        current.updatedAt = clock.now()
        try replaceRecordAndPublish(current, operation: .accept)
    }

    func finalizeAcceptAndApply(
        plan: ExternalReviewImportPlanV1,
        receipt: ExternalReviewImportReceiptV1,
        canonicalReceipt: PortableReviewMutationReceiptV1
    ) async throws {
        try plan.validate()
        try receipt.validate()
        guard canonicalReceipt.importReceipt == receipt,
              canonicalReceipt.mutationReceipt.mutationID == plan.mutationID,
              plan.mutationID == receipt.mutationID else {
            throw PortableExchangePersistenceFailureV2.invalidTransition
        }
        try ensureLoaded()
        guard var current = envelope?.sessions.first(where: {
            $0.namespace == .review &&
                $0.publicRequestID == plan.requestPublicID.rawValue
        }) else {
            throw PortableExchangePersistenceFailureV2.sessionNotFound
        }
        let effectDigest = Self.hexString(receipt.effectDigest)
        let importReceiptDigest = try receiptDigest(receipt)
        if current.pendingMutationID == nil {
            guard try hasStoredReconciliationReceipt(canonicalReceipt, in: current) else {
                throw PortableExchangePersistenceFailureV2.invalidTransition
            }
            return
        }
        guard current.pendingMutationID == plan.mutationID,
              current.pendingEffectSHA256 == effectDigest,
              current.pendingImportReceiptSHA256 == importReceiptDigest else {
            throw PortableExchangePersistenceFailureV2.invalidTransition
        }
        if try hasStoredReconciliationReceipt(canonicalReceipt, in: current) {
            let metadata = try responseMetadata(
                plan.responseRecord.canonicalResponse.canonicalBytes,
                fallbackResponseID: plan.responseRecord.recordID.uuidString.lowercased()
            )
            current.state = state(for: metadata.disposition)
            current.capabilityState = metadata.disposition == .acknowledged
                ? .responsePendingDecision
                : .historyOnlyTerminal
            if current.capabilityState == .historyOnlyTerminal,
               current.protectedCapability != nil {
                try removeCapability(for: current)
                current.protectedCapability = nil
            }
            current.pendingMutationID = nil
            current.pendingEffectSHA256 = nil
            current.pendingImportReceiptSHA256 = nil
            current.updatedAt = clock.now()
            try replaceRecordAndPublish(current, operation: .accept)
            return
        }
        let responseBytes = try canonicalData(canonicalReceipt)
        let responseReference = try persistImmutableBytes(
            responseBytes,
            role: .reconciliationReceipt,
            sessionID: current.sessionID
        )
        current.immutableBytes.append(responseReference)
        let metadata = try responseMetadata(
            plan.responseRecord.canonicalResponse.canonicalBytes,
            fallbackResponseID: plan.responseRecord.recordID.uuidString.lowercased()
        )
        current.state = state(for: metadata.disposition)
        if metadata.disposition == .acknowledged {
            current.capabilityState = .responsePendingDecision
        } else {
            current.capabilityState = .historyOnlyTerminal
            if current.protectedCapability != nil {
                try removeCapability(for: current)
                current.protectedCapability = nil
            }
        }
        current.pendingMutationID = nil
        current.pendingEffectSHA256 = nil
        current.pendingImportReceiptSHA256 = nil
        current.updatedAt = clock.now()
        try replaceRecordAndPublish(current, operation: .accept)
    }

    func finalizeSessionOnly(
        plan: ExternalReviewImportPlanV1,
        receipt: ExternalReviewImportReceiptV1
    ) async throws {
        try plan.validate()
        try receipt.validate()
        guard plan.decision != .acceptAndApply,
              receipt.decision == plan.decision,
              receipt.mutationID == plan.mutationID,
              receipt.workspaceID == plan.workspaceID,
              receipt.appliedWorkspaceRevision == nil else {
            throw PortableExchangePersistenceFailureV2.invalidTransition
        }
        switch plan.decision {
        case .discardUnimported:
            return
        case .keepQuarantined:
            try quarantine(
                plan.responseRecord.canonicalResponse.canonicalBytes,
                namespace: .review,
                reason: plan.disposition.rawValue
            )
        case .recordAsHistoryOnly:
            try ensureLoaded()
            guard let sessionID = envelope?.sessions.first(where: {
                $0.namespace == .review &&
                    $0.publicRequestID == plan.requestPublicID.rawValue
            })?.sessionID else {
                throw PortableExchangePersistenceFailureV2.sessionNotFound
            }
            let metadata = try responseMetadata(
                plan.responseRecord.canonicalResponse.canonicalBytes,
                fallbackResponseID: plan.responseRecord.recordID.uuidString.lowercased()
            )
            _ = try recordResponse(
                sessionID: sessionID,
                responsePublicID: metadata.id,
                responseBytes: plan.responseRecord.canonicalResponse.canonicalBytes,
                disposition: metadata.disposition,
                historyOnly: true
            )
        case .acceptAndApply:
            throw PortableExchangePersistenceFailureV2.invalidTransition
        }
    }

    func recoverAcceptAndApply(
        mutationID: MutationIDV1,
        canonicalReceipt: PortableReviewMutationReceiptV1?
    ) async throws {
        try ensureLoaded()
        guard var current = envelope?.sessions.first(where: {
            $0.pendingMutationID == mutationID
        }) else {
            // A completed record is idempotent only when its exact immutable
            // reconciliation bytes prove this mutation.  Never infer from an
            // unrelated terminal session.
            if let canonicalReceipt,
               (try? canonicalReceipt.mutationReceipt.validate()) != nil,
               (try? canonicalReceipt.importReceipt.validate()) != nil,
               canonicalReceipt.mutationReceipt.mutationID == mutationID,
               canonicalReceipt.importReceipt.mutationID == mutationID,
               try hasStoredReconciliationReceipt(
                   canonicalReceipt,
                   in: envelope?.sessions ?? []
               ) {
                return
            }
            throw PortableExchangePersistenceFailureV2.corruptStore
        }
        guard let canonicalReceipt else {
            // Without the canonical C14 receipt, recovery cannot distinguish
            // an applied effect from a prepared-only response.  Leave the
            // pending marker intact and fail closed for a later retry.
            throw PortableExchangePersistenceFailureV2.corruptStore
        }
        try canonicalReceipt.mutationReceipt.validate()
        try canonicalReceipt.importReceipt.validate()
        guard canonicalReceipt.mutationReceipt.mutationID == mutationID,
              canonicalReceipt.importReceipt.mutationID == mutationID,
              current.pendingEffectSHA256 == Self.hexString(canonicalReceipt.importReceipt.effectDigest),
              current.pendingImportReceiptSHA256 == try receiptDigest(canonicalReceipt.importReceipt) else {
            throw PortableExchangePersistenceFailureV2.invalidTransition
        }
        if try !hasStoredReconciliationReceipt(canonicalReceipt, in: current) {
            current.immutableBytes.append(try persistImmutableBytes(
                canonicalData(canonicalReceipt),
                role: .reconciliationReceipt,
                sessionID: current.sessionID
            ))
        }
        if let response = try? latestResponseMetadata(current) {
            current.state = state(for: response.disposition)
            if response.disposition == .acknowledged {
                current.capabilityState = .responsePendingDecision
            } else {
                current.capabilityState = .historyOnlyTerminal
            }
        } else {
            current.state = .historyOnlyTerminal
            current.capabilityState = .historyOnlyTerminal
        }
        if current.capabilityState == .historyOnlyTerminal,
           current.protectedCapability != nil {
            try removeCapability(for: current)
            current.protectedCapability = nil
        }
        current.pendingMutationID = nil
        current.pendingEffectSHA256 = nil
        current.pendingImportReceiptSHA256 = nil
        current.updatedAt = clock.now()
        try replaceRecordAndPublish(current, operation: .accept)
    }

    private struct ResponseMetadataV2 {
        let id: String
        let disposition: ReviewResponseDispositionV1
    }

    private func responseMetadata(
        _ bytes: Data,
        fallbackResponseID: String
    ) throws -> ResponseMetadataV2 {
        let payload = try PortableReviewCanonicalCodecV1.decodeCanonicalResponseRecord(bytes)
        switch payload {
        case let .portable(response):
            return ResponseMetadataV2(
                id: response.responsePublicID,
                disposition: response.body.disposition
            )
        case let .originRecorded(response):
            return ResponseMetadataV2(
                id: fallbackResponseID,
                disposition: response.responseBody.disposition
            )
        }
    }

    private func latestResponseMetadata(
        _ record: PortableExchangeSessionRecordV2
    ) throws -> ResponseMetadataV2 {
        guard let reference = record.immutableBytes.last(where: {
            $0.role == .acceptedResponse
        }) else {
            throw PortableExchangePersistenceFailureV2.invalidRecord
        }
        return try responseMetadata(
            readPayload(reference.relativePath),
            fallbackResponseID: record.responseIDs.last ?? record.publicRequestID
        )
    }

    private func hasStoredReconciliationReceipt(
        _ canonicalReceipt: PortableReviewMutationReceiptV1,
        in record: PortableExchangeSessionRecordV2
    ) throws -> Bool {
        try hasStoredReconciliationReceipt(canonicalReceipt, in: [record])
    }

    private func hasStoredReconciliationReceipt(
        _ canonicalReceipt: PortableReviewMutationReceiptV1,
        in records: [PortableExchangeSessionRecordV2]
    ) throws -> Bool {
        let expected = try canonicalData(canonicalReceipt)
        let expectedSHA256 = StoreMigrationCanonicalJSONV1.sha256(expected)
        for record in records {
            for reference in record.immutableBytes where reference.role == .reconciliationReceipt {
                let bytes = try readPayload(reference.relativePath)
                guard UInt64(bytes.count) == reference.byteCount,
                      StoreMigrationCanonicalJSONV1.sha256(bytes) == reference.sha256 else {
                    throw PortableExchangePersistenceFailureV2.corruptStore
                }
                if reference.sha256 == expectedSHA256 && bytes == expected {
                    return true
                }
            }
        }
        return false
    }

    private func responseID(
        for record: ExternalReviewResponseRecordV1
    ) -> String {
        (try? responseMetadata(
            record.canonicalResponse.canonicalBytes,
            fallbackResponseID: record.recordID.uuidString.lowercased()
        ).id) ?? record.recordID.uuidString.lowercased()
    }

    private func receiptDigest(
        _ receipt: ExternalReviewImportReceiptV1
    ) throws -> String {
        StoreMigrationCanonicalJSONV1.sha256(try canonicalData(receipt))
    }

    private static func hexString(_ value: Data) -> String {
        value.map { String(format: "%02x", $0) }.joined()
    }
}

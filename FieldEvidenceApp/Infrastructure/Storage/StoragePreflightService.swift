import Foundation

enum StoragePreflightError: Error, Equatable, LocalizedError {
    case capacityUnavailable
    case capacityEstimateOverflow
    case insufficientCapacity(requiredBytes: Int64, availableBytes: Int64)

    var errorDescription: String? {
        switch self {
        case .capacityUnavailable:
            "Available storage could not be checked. Retry before importing the photo."
        case .capacityEstimateOverflow:
            "The required storage could not be calculated safely."
        case .insufficientCapacity:
            "More device storage is needed. Free space, then retry the photo import."
        }
    }
}

struct StoragePreflightService {
    typealias CapacityProvider = (URL) throws -> Int64?

    static let evidenceAcceptanceEstimateBytes: Int64 = 68 * 1_048_576
    static let pdfOperationAllowanceBytes: Int64 = 32 * 1_048_576
    static let reserveBytes: Int64 = 64 * 1_048_576
    static let evidenceAcceptanceRequiredBytes = evidenceAcceptanceEstimateBytes + reserveBytes

    private let capacityProvider: CapacityProvider

    init(
        capacityProvider: @escaping CapacityProvider = { targetURL in
            try targetURL.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            ).volumeAvailableCapacityForImportantUsage
        }
    ) {
        self.capacityProvider = capacityProvider
    }

    func checkEvidenceAcceptance(onVolumeContaining generationRootURL: URL) throws {
        try check(
            requiredBytes: Self.evidenceAcceptanceRequiredBytes,
            onVolumeContaining: generationRootURL
        )
    }

    func pdfRequiredBytes(referencedImageByteCount: Int64) throws -> Int64 {
        guard referencedImageByteCount >= 0 else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (duplicatedImageBytes, multiplicationOverflow) = referencedImageByteCount
            .multipliedReportingOverflow(by: 2)
        guard !multiplicationOverflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (withOperationAllowance, operationOverflow) = duplicatedImageBytes
            .addingReportingOverflow(Self.pdfOperationAllowanceBytes)
        guard !operationOverflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (requiredBytes, reserveOverflow) = withOperationAllowance
            .addingReportingOverflow(Self.reserveBytes)
        guard !reserveOverflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        return requiredBytes
    }

    func checkPDFGeneration(
        referencedImageByteCount: Int64,
        onVolumeContaining generationRootURL: URL
    ) throws {
        try check(
            requiredBytes: pdfRequiredBytes(
                referencedImageByteCount: referencedImageByteCount
            ),
            onVolumeContaining: generationRootURL
        )
    }

    func backupRequiredBytes(declaredPayloadByteCount: Int64) throws -> Int64 {
        guard declaredPayloadByteCount >= 0 else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (roundedDividend, roundingOverflow) = declaredPayloadByteCount
            .addingReportingOverflow(4)
        guard !roundingOverflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let overhead = roundedDividend / 5
        let (estimatedBytes, estimateOverflow) = declaredPayloadByteCount
            .addingReportingOverflow(overhead)
        guard !estimateOverflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (requiredBytes, reserveOverflow) = estimatedBytes.addingReportingOverflow(
            Self.reserveBytes
        )
        guard !reserveOverflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        return requiredBytes
    }

    func checkBackupExport(
        declaredPayloadByteCount: Int64,
        onVolumeContaining destinationURL: URL
    ) throws {
        try check(
            requiredBytes: backupRequiredBytes(
                declaredPayloadByteCount: declaredPayloadByteCount
            ),
            onVolumeContaining: destinationURL
        )
    }

    func restoreRequiredBytes(declaredPayloadByteCount: Int64) throws -> Int64 {
        guard declaredPayloadByteCount >= 0 else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (stagedAndGenerationBytes, multiplicationOverflow) =
            declaredPayloadByteCount.multipliedReportingOverflow(by: 2)
        guard !multiplicationOverflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (roundedDividend, roundingOverflow) = declaredPayloadByteCount
            .addingReportingOverflow(4)
        guard !roundingOverflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let validationAllowance = roundedDividend / 5
        let (withValidationAllowance, allowanceOverflow) = stagedAndGenerationBytes
            .addingReportingOverflow(validationAllowance)
        guard !allowanceOverflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (requiredBytes, reserveOverflow) = withValidationAllowance
            .addingReportingOverflow(Self.reserveBytes)
        guard !reserveOverflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        return requiredBytes
    }

    func checkBackupImport(
        declaredPayloadByteCount: Int64,
        onVolumeContaining stagingURL: URL
    ) throws {
        try check(
            requiredBytes: restoreRequiredBytes(
                declaredPayloadByteCount: declaredPayloadByteCount
            ),
            onVolumeContaining: stagingURL
        )
    }

    func storageAdmissionRequiredBytes(
        requestedBytes: Int64,
        alreadyReservedBytes: Int64
    ) throws -> Int64 {
        guard requestedBytes >= 0, alreadyReservedBytes >= 0 else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (required, overflow) = requestedBytes.addingReportingOverflow(
            alreadyReservedBytes
        )
        guard !overflow, required >= 0 else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        return required
    }

    /// Reserves no bytes itself. The caller owns attempt identity and releases
    /// its process-local reservation; this method is the single volume-capacity
    /// refusal policy used immediately before canonical mutation.
    func checkStorageAdmission(
        requestedBytes: Int64,
        alreadyReservedBytes: Int64,
        onVolumeContaining targetURL: URL
    ) throws {
        try check(
            requiredBytes: storageAdmissionRequiredBytes(
                requestedBytes: requestedBytes,
                alreadyReservedBytes: alreadyReservedBytes
            ),
            onVolumeContaining: targetURL
        )
    }

    func scratchRequiredBytes(requestedByteCount: UInt64) throws -> Int64 {
        guard requestedByteCount > 0,
              requestedByteCount <= UInt64(Int64.max) else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let requested = Int64(requestedByteCount)
        let (required, overflow) = requested.addingReportingOverflow(
            Self.reserveBytes
        )
        guard !overflow, required > 0 else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        return required
    }

    func checkScratchLease(
        requestedByteCount: UInt64,
        onVolumeContaining scratchRootURL: URL
    ) throws {
        try check(
            requiredBytes: scratchRequiredBytes(
                requestedByteCount: requestedByteCount
            ),
            onVolumeContaining: scratchRootURL
        )
    }

    func checkDeviceOperationalWrite(
        byteCount: UInt64,
        onVolumeContaining operationalRootURL: URL
    ) throws {
        try check(
            requiredBytes: scratchRequiredBytes(requestedByteCount: byteCount),
            onVolumeContaining: operationalRootURL
        )
    }

    private func check(requiredBytes: Int64, onVolumeContaining targetURL: URL) throws {
        guard let availableBytes = try capacityProvider(targetURL) else {
            throw StoragePreflightError.capacityUnavailable
        }
        guard availableBytes >= requiredBytes else {
            throw StoragePreflightError.insufficientCapacity(
                requiredBytes: requiredBytes,
                availableBytes: availableBytes
            )
        }
    }
}

// MARK: - C36 draft attachment admission

extension StoragePreflightService {
    /// Draft capture has two local byte boundaries: disposable scratch and
    /// durable per-item staging.  The caller supplies the item size once;
    /// overflow and zero-byte inputs are rejected before either writer runs.
    func draftAttachmentRequiredBytes(byteCount: Int64) throws -> Int64 {
        guard byteCount > 0 else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (stagingAndScratch, overflow) = byteCount.multipliedReportingOverflow(by: 2)
        guard !overflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (required, reserveOverflow) = stagingAndScratch
            .addingReportingOverflow(Self.reserveBytes)
        guard !reserveOverflow, required > 0 else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        return required
    }

    func checkDraftAttachment(
        byteCount: Int64,
        onVolumeContaining stagingRootURL: URL
    ) throws {
        try check(
            requiredBytes: draftAttachmentRequiredBytes(byteCount: byteCount),
            onVolumeContaining: stagingRootURL
        )
    }

    static let c36StagingExcludedFromBackup = true
    static let c36StoragePressureIsRetryable = true
}

// MARK: - C34 scene-navigation storage preflight boundary

enum C34SceneNavigationStoragePreflightBoundaryV1 {
    static let snapshotType: Any.Type = SceneNavigationSnapshotV1.self
    static let canonicalWorkspaceReservationRequired = false
    static let reportStorageReservationRequired = false
    static let backupStorageReservationRequired = false
    static let corruptOrFuturePayloadIsDiscarded = true
    static let automaticWorkMayStartDuringReconciliation = false

    static func validate(_ lifecycle: SceneNavigationLifecycleDispositionV1 = .init()) -> Bool {
        lifecycle.tolerantDecode && lifecycle.eraseClears
            && !lifecycle.workspaceTruth
            && !canonicalWorkspaceReservationRequired
            && !reportStorageReservationRequired
            && !backupStorageReservationRequired
    }
}

// MARK: - C54 encrypted portable envelope admission

extension StoragePreflightService {
    static let encryptedPortableEnvelopeFramePlaintextBytes: Int64 = 1_048_576
    static let encryptedPortableEnvelopeAuthenticationTagBytes: Int64 = 16
    static let encryptedPortableEnvelopeFrameHeaderBytes: Int64 = 12
    static let encryptedPortableEnvelopeMaximumHeaderBytes: Int64 = 65_536

    /// Computes the complete output reservation before a KDF, allocation,
    /// preview, or writer is entered. The one final empty frame is included
    /// for a zero-byte inner stream and every arithmetic edge fails closed.
    func encryptedPortableEnvelopeRequiredBytes(
        innerByteCount: Int64,
        headerByteCount: Int64
    ) throws -> Int64 {
        guard innerByteCount >= 0,
              headerByteCount > 0,
              headerByteCount <= Self.encryptedPortableEnvelopeMaximumHeaderBytes else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let frameCount: Int64
        if innerByteCount == 0 {
            frameCount = 1
        } else {
            let (rounded, roundingOverflow) = innerByteCount.addingReportingOverflow(
                Self.encryptedPortableEnvelopeFramePlaintextBytes - 1
            )
            guard !roundingOverflow else {
                throw StoragePreflightError.capacityEstimateOverflow
            }
            frameCount = rounded / Self.encryptedPortableEnvelopeFramePlaintextBytes
        }
        guard frameCount > 0, frameCount <= Int64(UInt32.max) else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (perFrameBytes, perFrameOverflow) =
            Self.encryptedPortableEnvelopeAuthenticationTagBytes.addingReportingOverflow(
                Self.encryptedPortableEnvelopeFrameHeaderBytes
            )
        guard !perFrameOverflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (framingBytes, framingOverflow) = frameCount.multipliedReportingOverflow(
            by: perFrameBytes
        )
        guard !framingOverflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (withHeader, headerOverflow) = innerByteCount.addingReportingOverflow(
            headerByteCount
        )
        guard !headerOverflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (outputBytes, framingAdditionOverflow) = withHeader.addingReportingOverflow(
            framingBytes
        )
        guard !framingAdditionOverflow else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (requiredBytes, reserveOverflow) = outputBytes.addingReportingOverflow(
            Self.reserveBytes
        )
        guard !reserveOverflow, requiredBytes > 0 else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        return requiredBytes
    }

    func checkEncryptedPortableEnvelope(
        innerByteCount: Int64,
        headerByteCount: Int64,
        onVolumeContaining scratchRootURL: URL
    ) throws {
        try check(
            requiredBytes: encryptedPortableEnvelopeRequiredBytes(
                innerByteCount: innerByteCount,
                headerByteCount: headerByteCount
            ),
            onVolumeContaining: scratchRootURL
        )
    }

    static let c54PreflightPrecedesKDFAllocationPreviewAndWrite = true
    static let c54ScratchIsProtectedAndBackupExcluded = true

    func encryptedPortableEnvelopeStreamingRequiredBytes(
        plaintextByteCount: UInt64,
        envelopeByteCount: UInt64
    ) throws -> Int64 {
        guard plaintextByteCount <= EncryptedPortableEnvelopeResourceLimitsV1.maximumOperationalPlaintextByteCount,
              envelopeByteCount <= EncryptedPortableEnvelopeResourceLimitsV1.maximumOperationalScratchByteCount,
              plaintextByteCount <= UInt64(Int64.max), envelopeByteCount <= UInt64(Int64.max) else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (scratchBytes, scratchOverflow) = Int64(plaintextByteCount)
            .addingReportingOverflow(Int64(envelopeByteCount))
        let (required, reserveOverflow) = scratchBytes.addingReportingOverflow(Self.reserveBytes)
        guard !scratchOverflow, !reserveOverflow, required > 0 else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        return required
    }

    func checkEncryptedPortableEnvelopeStreaming(
        plaintextByteCount: UInt64,
        envelopeByteCount: UInt64,
        onVolumeContaining scratchRootURL: URL
    ) throws {
        try check(
            requiredBytes: encryptedPortableEnvelopeStreamingRequiredBytes(
                plaintextByteCount: plaintextByteCount,
                envelopeByteCount: envelopeByteCount
            ),
            onVolumeContaining: scratchRootURL
        )
    }

    func encryptedPortableEnvelopeOpenStreamingRequiredBytes(
        plaintextByteCount: UInt64
    ) throws -> Int64 {
        guard plaintextByteCount <= EncryptedPortableEnvelopeResourceLimitsV1.maximumOperationalPlaintextByteCount,
              plaintextByteCount <= UInt64(Int64.max) else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        let (required, overflow) = Int64(plaintextByteCount)
            .addingReportingOverflow(Self.reserveBytes)
        guard !overflow, required > 0 else {
            throw StoragePreflightError.capacityEstimateOverflow
        }
        return required
    }

    func checkEncryptedPortableEnvelopeOpenStreaming(
        plaintextByteCount: UInt64,
        onVolumeContaining scratchRootURL: URL
    ) throws {
        try check(
            requiredBytes: encryptedPortableEnvelopeOpenStreamingRequiredBytes(
                plaintextByteCount: plaintextByteCount
            ),
            onVolumeContaining: scratchRootURL
        )
    }
}

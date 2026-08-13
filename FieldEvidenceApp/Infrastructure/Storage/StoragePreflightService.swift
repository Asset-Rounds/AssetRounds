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

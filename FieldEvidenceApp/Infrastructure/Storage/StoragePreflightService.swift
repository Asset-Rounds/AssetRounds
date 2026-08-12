import Foundation

enum StoragePreflightError: Error, Equatable, LocalizedError {
    case capacityUnavailable
    case insufficientCapacity(requiredBytes: Int64, availableBytes: Int64)

    var errorDescription: String? {
        switch self {
        case .capacityUnavailable:
            "Available storage could not be checked. Retry before importing the photo."
        case .insufficientCapacity:
            "More device storage is needed. Free space, then retry the photo import."
        }
    }
}

struct StoragePreflightService {
    typealias CapacityProvider = (URL) throws -> Int64?

    static let evidenceAcceptanceEstimateBytes: Int64 = 68 * 1_048_576
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
        guard let availableBytes = try capacityProvider(generationRootURL) else {
            throw StoragePreflightError.capacityUnavailable
        }
        guard availableBytes >= Self.evidenceAcceptanceRequiredBytes else {
            throw StoragePreflightError.insufficientCapacity(
                requiredBytes: Self.evidenceAcceptanceRequiredBytes,
                availableBytes: availableBytes
            )
        }
    }
}

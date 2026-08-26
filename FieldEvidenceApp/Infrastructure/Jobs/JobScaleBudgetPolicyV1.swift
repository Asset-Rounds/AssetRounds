import Foundation

enum JobScaleFixtureV1: String, Codable, CaseIterable, Hashable, Sendable {
    case oneAsset = "ASSET_1"
    case hundredAssets = "ASSET_100"
    case tenThousandAssets = "ASSET_10000"
    case largeMediaProxy = "LARGE_MEDIA_PROXY"
}

struct JobScaleBudgetV1: Codable, Equatable, Sendable {
    let fixture: JobScaleFixtureV1
    let assetCount: Int
    let proxyByteCount: Int64
    let maximumConcurrency: Int
    let chunkByteCount: Int
    let maximumResidentMemoryBytes: Int64
    let p50LatencyMilliseconds: Int
    let p95LatencyMilliseconds: Int
    let maximumInitialStallMilliseconds: Int
    let progressHeartbeatMilliseconds: Int
}

enum JobScaleBudgetPolicyV1 {
    static let version = 1
    static let maximumRunnerConcurrency = 2
    static let maximumStagingPathDepth = 16
    static let maximumStagingCleanupEntryCount = 100_000

    static let frozen: [JobScaleBudgetV1] = [
        JobScaleBudgetV1(
            fixture: .oneAsset, assetCount: 1, proxyByteCount: 0,
            maximumConcurrency: 1, chunkByteCount: 256 * 1024,
            maximumResidentMemoryBytes: 64 * 1024 * 1024,
            p50LatencyMilliseconds: 250, p95LatencyMilliseconds: 1_000,
            maximumInitialStallMilliseconds: 250,
            progressHeartbeatMilliseconds: 500
        ),
        JobScaleBudgetV1(
            fixture: .hundredAssets, assetCount: 100, proxyByteCount: 0,
            maximumConcurrency: 2, chunkByteCount: 512 * 1024,
            maximumResidentMemoryBytes: 128 * 1024 * 1024,
            p50LatencyMilliseconds: 2_000, p95LatencyMilliseconds: 5_000,
            maximumInitialStallMilliseconds: 500,
            progressHeartbeatMilliseconds: 1_000
        ),
        JobScaleBudgetV1(
            fixture: .tenThousandAssets, assetCount: 10_000, proxyByteCount: 0,
            maximumConcurrency: 2, chunkByteCount: 512 * 1024,
            maximumResidentMemoryBytes: 192 * 1024 * 1024,
            p50LatencyMilliseconds: 15_000, p95LatencyMilliseconds: 30_000,
            maximumInitialStallMilliseconds: 1_000,
            progressHeartbeatMilliseconds: 2_000
        ),
        JobScaleBudgetV1(
            fixture: .largeMediaProxy, assetCount: 1,
            proxyByteCount: 512 * 1024 * 1024,
            maximumConcurrency: 1, chunkByteCount: 1024 * 1024,
            maximumResidentMemoryBytes: 128 * 1024 * 1024,
            p50LatencyMilliseconds: 10_000, p95LatencyMilliseconds: 25_000,
            maximumInitialStallMilliseconds: 1_000,
            progressHeartbeatMilliseconds: 2_000
        )
    ]

    static func budget(for fixture: JobScaleFixtureV1) -> JobScaleBudgetV1 {
        // Exhaustive switch avoids a trap if the table is edited incorrectly.
        switch fixture {
        case .oneAsset: frozen[0]
        case .hundredAssets: frozen[1]
        case .tenThousandAssets: frozen[2]
        case .largeMediaProxy: frozen[3]
        }
    }

    static func validateFrozenPolicy() throws {
        guard version == 1,
              (1...64).contains(maximumStagingPathDepth),
              (1...1_000_000).contains(maximumStagingCleanupEntryCount),
              Set(frozen.map(\.fixture)) == Set(JobScaleFixtureV1.allCases),
              frozen.count == JobScaleFixtureV1.allCases.count,
              frozen.allSatisfy({
                  $0.assetCount > 0 && $0.proxyByteCount >= 0
                      && (1...maximumRunnerConcurrency).contains($0.maximumConcurrency)
                      && $0.chunkByteCount > 0
                      && $0.maximumResidentMemoryBytes >= Int64($0.chunkByteCount)
                      && $0.p50LatencyMilliseconds > 0
                      && $0.p95LatencyMilliseconds >= $0.p50LatencyMilliseconds
                      && $0.maximumInitialStallMilliseconds > 0
                      && $0.progressHeartbeatMilliseconds > 0
              }) else {
            throw LocalJobValidationFailureV1.invalidContract
        }
    }
}

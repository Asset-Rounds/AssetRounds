import Foundation
import OSLog

enum DiagnosticsLogEvent: Equatable, Sendable {
    case countersWriteFailed
    case invalidCountersReset
    case metricValueDiscarded
    case encryptedEnvelopeFailure(
        stage: C54EncryptedPortableEnvelopeDiagnosticStageV1,
        category: C54EncryptedPortableEnvelopeDiagnosticCategoryV1
    )
    case encryptedEnvelopeLifecycle(
        classification: C54EncryptedPortableEnvelopeLifecycleClassificationV1
    )
}

extension DiagnosticsLogEvent {
    /// Builds the sole encrypted-envelope external-failure event.  The
    /// category is intentionally not caller-controlled: wrong passphrases and
    /// damaged/tampered envelopes share one neutral diagnostic outcome.
    static func encryptedEnvelopeWrongPassphraseOrDamage(
        stage: C54EncryptedPortableEnvelopeDiagnosticStageV1
    ) -> Self {
        .encryptedEnvelopeFailure(
            stage: stage,
            category: .wrongPassphraseOrDamage
        )
    }

    static func c54EncryptedEnvelopeFailure(
        stage: C54EncryptedPortableEnvelopeDiagnosticStageV1
    ) -> Self {
        encryptedEnvelopeWrongPassphraseOrDamage(stage: stage)
    }
}

enum OperationalLogCodeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case countersWriteFailed = "COUNTERS_WRITE_FAILED"
    case invalidCountersReset = "INVALID_COUNTERS_RESET"
    case metricValueDiscarded = "METRIC_VALUE_DISCARDED"
    case operationalFailureRecorded = "OPERATIONAL_FAILURE_RECORDED"
    case scratchLeaseCleanupFailed = "SCRATCH_LEASE_CLEANUP_FAILED"
    case supportExportFailed = "SUPPORT_EXPORT_FAILED"
}

enum OperationalLogLevelV1: String, CaseIterable, Codable, Hashable, Sendable {
    case error = "ERROR"
    case fault = "FAULT"
    case info = "INFO"
}

struct OperationalLogDescriptorV1: Codable, Equatable, Sendable {
    let code: OperationalLogCodeV1
    let category: String
    let level: OperationalLogLevelV1
    let staticMessage: String
    let privacyClass: OperationalPrivacyClassV1
}

enum OperationalLogRegistryV1 {
    static let version = 1
    static let descriptors: [OperationalLogDescriptorV1] = [
        .init(code: .countersWriteFailed, category: "Diagnostics", level: .fault, staticMessage: "Diagnostics counters could not be saved.", privacyClass: .publicSystem),
        .init(code: .invalidCountersReset, category: "Diagnostics", level: .fault, staticMessage: "Invalid diagnostics counters were reset.", privacyClass: .publicSystem),
        .init(code: .metricValueDiscarded, category: "Diagnostics", level: .error, staticMessage: "A diagnostic metric value was discarded.", privacyClass: .publicSystem),
        .init(code: .operationalFailureRecorded, category: "Operations", level: .info, staticMessage: "A bounded operational failure was recorded.", privacyClass: .publicSystem),
        .init(code: .scratchLeaseCleanupFailed, category: "Scratch", level: .fault, staticMessage: "Scratch lease cleanup failed.", privacyClass: .publicSystem),
        .init(code: .supportExportFailed, category: "SupportExport", level: .error, staticMessage: "Support export failed.", privacyClass: .publicSystem),
    ]

    static func descriptor(for code: OperationalLogCodeV1) throws
        -> OperationalLogDescriptorV1 {
        let matches = descriptors.filter { $0.code == code }
        guard matches.count == 1, let value = matches.first else {
            throw OperationalDiagnosticsValidationFailureV1.registryMismatch
        }
        return value
    }

    static func validate() throws {
        guard descriptors.count == OperationalLogCodeV1.allCases.count,
              Set(descriptors.map(\.code)).count == descriptors.count,
              descriptors.allSatisfy({
                  OperationalDiagnosticsBoundsV1.validToken($0.category)
                      && !$0.staticMessage.isEmpty
                      && $0.staticMessage.utf8.count <= 256
                      && $0.privacyClass == .publicSystem
              }) else {
            throw OperationalDiagnosticsValidationFailureV1.registryMismatch
        }
    }
}

enum OSLogEmissionPolicyV1 {
    static let permitsDynamicMessages = false
    static let permitsCustomerContent = false
    static let permitsCustomerIdentifiers = false
    static let permitsRawLogExport = false
    static let maximumStaticMessageBytes = 256
}

enum PerformanceSignpostIntervalV1: String, CaseIterable, Codable, Hashable, Sendable {
    case appBootstrap = "APP_BOOTSTRAP"
    case backup = "BACKUP"
    case contentDerivative = "CONTENT_DERIVATIVE"
    case contentIngest = "CONTENT_INGEST"
    case diagnosticsStoreWrite = "DIAGNOSTICS_STORE_WRITE"
    case finalization = "FINALIZATION"
    case importCommit = "IMPORT_COMMIT"
    case importParse = "IMPORT_PARSE"
    case mutationCommit = "MUTATION_COMMIT"
    case reportRender = "REPORT_RENDER"
    case restore = "RESTORE"
    case searchRebuild = "SEARCH_REBUILD"
    case scratchLease = "SCRATCH_LEASE"
    case storeOpen = "STORE_OPEN"
    case supportExport = "SUPPORT_EXPORT"
}

enum PerformanceSignpostExportDispositionV1: String, Codable, Hashable, Sendable {
    case excluded = "EXCLUDED"
}

enum PerformanceSignpostRetentionV1: String, Codable, Hashable, Sendable {
    case memoryOnly = "MEMORY_ONLY"
}

enum PerformanceSignpostPrivacyV1: String, Codable, Hashable, Sendable {
    case staticCodeOnly = "STATIC_CODE_ONLY"
}

enum PerformanceSignpostCardinalityV1: String, Codable, Hashable, Sendable {
    case bounded = "BOUNDED"
}

struct PerformanceSignpostDescriptorV1: Codable, Equatable, Sendable {
    let interval: PerformanceSignpostIntervalV1
    let staticName: String
    let owner: OperationalOwnerV1
    let exportDisposition: PerformanceSignpostExportDispositionV1
    let retention: PerformanceSignpostRetentionV1
    let privacy: PerformanceSignpostPrivacyV1
    let cardinality: PerformanceSignpostCardinalityV1

    init(
        interval: PerformanceSignpostIntervalV1,
        staticName: String,
        owner: OperationalOwnerV1
    ) {
        self.interval = interval
        self.staticName = staticName
        self.owner = owner
        exportDisposition = .excluded
        retention = .memoryOnly
        privacy = .staticCodeOnly
        cardinality = .bounded
    }
}

enum PerformanceSignpostRegistryV1 {
    static let version = 1
    static let descriptors: [PerformanceSignpostDescriptorV1] = [
        .init(interval: .appBootstrap, staticName: "app_bootstrap", owner: .deviceLifecycle),
        .init(interval: .backup, staticName: "backup", owner: .backup),
        .init(interval: .contentDerivative, staticName: "content_derivative", owner: .persistence),
        .init(interval: .contentIngest, staticName: "content_ingest", owner: .persistence),
        .init(interval: .diagnosticsStoreWrite, staticName: "diagnostics_store_write", owner: .diagnosticsStore),
        .init(interval: .finalization, staticName: "finalization", owner: .reporting),
        .init(interval: .importCommit, staticName: "import_commit", owner: .backup),
        .init(interval: .importParse, staticName: "import_parse", owner: .backup),
        .init(interval: .mutationCommit, staticName: "mutation_commit", owner: .persistence),
        .init(interval: .reportRender, staticName: "report_render", owner: .reporting),
        .init(interval: .restore, staticName: "restore", owner: .backup),
        .init(interval: .searchRebuild, staticName: "search_rebuild", owner: .persistence),
        .init(interval: .scratchLease, staticName: "scratch_lease", owner: .scratchStore),
        .init(interval: .storeOpen, staticName: "store_open", owner: .persistence),
        .init(interval: .supportExport, staticName: "support_export", owner: .supportExport),
    ]

    static func validate() throws {
        guard descriptors.count == PerformanceSignpostIntervalV1.allCases.count,
              Set(descriptors.map(\.interval)).count == descriptors.count,
              descriptors.allSatisfy({
                  OperationalDiagnosticsBoundsV1.validToken($0.staticName)
                      && $0.exportDisposition == .excluded
                      && $0.retention == .memoryOnly
                      && $0.privacy == .staticCodeOnly
                      && $0.cardinality == .bounded
              }) else {
            throw OperationalDiagnosticsValidationFailureV1.registryMismatch
        }
    }
}

enum PerformanceSignpostPolicyV1 {
    static let requiresBalancedBeginEnd = true
    static let permitsDynamicNames = false
    static let permitsCustomerContent = false
    static let permitsCustomerIdentifiers = false
}

enum PerformanceSignpostRecorderFailureV1: Error, Equatable, Sendable {
    case duplicateToken
    case eventLimitExceeded
    case intervalMismatch
    case unbalancedIntervals
    case unknownToken
}

struct PerformanceSignpostTokenV1: Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let interval: PerformanceSignpostIntervalV1
}

enum PerformanceSignpostPhaseV1: String, Codable, Hashable, Sendable {
    case begin = "BEGIN"
    case endCancelled = "END_CANCELLED"
    case endFailure = "END_FAILURE"
    case endSuccess = "END_SUCCESS"
}

enum PerformanceSignpostEndOutcomeV1: String, Codable, Hashable, Sendable {
    case cancelled = "CANCELLED"
    case failure = "FAILURE"
    case success = "SUCCESS"

    var phase: PerformanceSignpostPhaseV1 {
        switch self {
        case .cancelled: return .endCancelled
        case .failure: return .endFailure
        case .success: return .endSuccess
        }
    }
}

struct PerformanceSignpostEventV1: Codable, Equatable, Sendable {
    let token: PerformanceSignpostTokenV1
    let phase: PerformanceSignpostPhaseV1
}

struct PerformanceSignpostSnapshotV1: Equatable, Sendable {
    let events: [PerformanceSignpostEventV1]
    let activeTokens: [PerformanceSignpostTokenV1]

    var isBalanced: Bool { activeTokens.isEmpty }
}

/// Deterministic inspection seam. It records only closed interval identifiers
/// and phases; it accepts no names, metadata, customer values, or timestamps.
final class PerformanceSignpostRecorderV1: @unchecked Sendable {
    static let maximumEventCount = 1_024
    static let maximumActiveIntervalCount = 128

    private let lock = NSLock()
    private var events: [PerformanceSignpostEventV1] = []
    private var active: [UUID: PerformanceSignpostTokenV1] = [:]

    func begin(
        _ interval: PerformanceSignpostIntervalV1,
        tokenID: UUID
    ) throws -> PerformanceSignpostTokenV1 {
        lock.lock()
        defer { lock.unlock() }
        guard active[tokenID] == nil else {
            throw PerformanceSignpostRecorderFailureV1.duplicateToken
        }
        let (reservedCount, reserveOverflow) = events.count.addingReportingOverflow(
            active.count
        )
        guard active.count < Self.maximumActiveIntervalCount,
              !reserveOverflow,
              reservedCount <= Self.maximumEventCount - 2 else {
            throw PerformanceSignpostRecorderFailureV1.eventLimitExceeded
        }
        let token = PerformanceSignpostTokenV1(id: tokenID, interval: interval)
        active[tokenID] = token
        events.append(.init(token: token, phase: .begin))
        return token
    }

    func end(
        _ token: PerformanceSignpostTokenV1,
        outcome: PerformanceSignpostEndOutcomeV1 = .success
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let current = active[token.id] else {
            throw PerformanceSignpostRecorderFailureV1.unknownToken
        }
        guard current.interval == token.interval else {
            throw PerformanceSignpostRecorderFailureV1.intervalMismatch
        }
        guard events.count < Self.maximumEventCount else {
            throw PerformanceSignpostRecorderFailureV1.eventLimitExceeded
        }
        active[token.id] = nil
        events.append(.init(token: token, phase: outcome.phase))
    }

    func snapshot(requireBalanced: Bool = false) throws
        -> PerformanceSignpostSnapshotV1 {
        lock.lock()
        defer { lock.unlock() }
        let snapshot = PerformanceSignpostSnapshotV1(
            events: events,
            activeTokens: active.values.sorted {
                $0.id.uuidString < $1.id.uuidString
            }
        )
        if requireBalanced, !snapshot.isBalanced {
            throw PerformanceSignpostRecorderFailureV1.unbalancedIntervals
        }
        return snapshot
    }
}

struct DiagnosticsLogger: Sendable {
    typealias Sink = @Sendable (DiagnosticsLogEvent) -> Void
    typealias OperationalSink = @Sendable (OperationalLogCodeV1) -> Void

    static let live = DiagnosticsLogger()

    private let sink: Sink
    private let operationalSink: OperationalSink

    init() {
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "FieldEvidenceApp",
            category: "Diagnostics"
        )
        sink = { event in
            switch event {
            case .countersWriteFailed:
                logger.fault("Diagnostics counters could not be saved.")
            case .invalidCountersReset:
                logger.fault("Invalid diagnostics counters were reset.")
            case .metricValueDiscarded:
                logger.error("A diagnostic metric value was discarded.")
            case .encryptedEnvelopeFailure, .encryptedEnvelopeLifecycle:
                logger.error("An encrypted-envelope operation ended at a bounded diagnostic boundary.")
            }
        }
        operationalSink = { code in
            switch code {
            case .countersWriteFailed:
                logger.fault("Diagnostics counters could not be saved.")
            case .invalidCountersReset:
                logger.fault("Invalid diagnostics counters were reset.")
            case .metricValueDiscarded:
                logger.error("A diagnostic metric value was discarded.")
            case .operationalFailureRecorded:
                logger.info("A bounded operational failure was recorded.")
            case .scratchLeaseCleanupFailed:
                logger.fault("Scratch lease cleanup failed.")
            case .supportExportFailed:
                logger.error("Support export failed.")
            }
        }
    }

    init(
        sink: @escaping Sink,
        operationalSink: @escaping OperationalSink = { _ in }
    ) {
        self.sink = sink
        self.operationalSink = operationalSink
    }

    func record(_ event: DiagnosticsLogEvent) {
        sink(event)
    }

    func record(
        _ classification: C54EncryptedPortableEnvelopeDiagnosticClassificationV1
    ) {
        sink(.encryptedEnvelopeFailure(
            stage: classification.stage,
            category: classification.category
        ))
    }

    func record(
        _ classification: C54EncryptedPortableEnvelopeLifecycleClassificationV1
    ) {
        sink(.encryptedEnvelopeLifecycle(classification: classification))
    }

    func record(_ code: OperationalLogCodeV1) {
        operationalSink(code)
    }

    /// Records only static C54 stage/category labels.  No envelope bytes,
    /// passphrase, key, digest, metadata, identity, filename, or path reaches
    /// the OSLog sink.
    func recordEncryptedEnvelopeFailure(
        at stage: C54EncryptedPortableEnvelopeDiagnosticStageV1
    ) {
        record(.encryptedEnvelopeWrongPassphraseOrDamage(stage: stage))
    }

    func recordEncryptedEnvelopeFailure(
        at stage: C54EncryptedPortableEnvelopeDiagnosticStageV1,
        category: C54EncryptedPortableEnvelopeDiagnosticCategoryV1
    ) {
        guard category == .wrongPassphraseOrDamage else { return }
        record(.encryptedEnvelopeFailure(stage: stage, category: category))
    }

    func recordEncryptedEnvelopeFailure(
        stage: C54EncryptedPortableEnvelopeDiagnosticStageV1,
        category: C54EncryptedPortableEnvelopeDiagnosticCategoryV1 =
            .wrongPassphraseOrDamage
    ) {
        recordEncryptedEnvelopeFailure(at: stage, category: category)
    }

    func recordC54EncryptedEnvelopeFailure(
        at stage: C54EncryptedPortableEnvelopeDiagnosticStageV1
    ) {
        recordEncryptedEnvelopeFailure(at: stage)
    }

    /// Lifecycle classification is observation-only.  Secret revocation and
    /// scratch cleanup stay owned by the encrypted-envelope operation.
    func recordEncryptedEnvelopeLifecycle(
        _ classification: C54EncryptedPortableEnvelopeLifecycleClassificationV1
    ) {
        record(.encryptedEnvelopeLifecycle(classification: classification))
    }

    func recordC54EncryptedEnvelopeLifecycle(
        _ classification: C54EncryptedPortableEnvelopeLifecycleClassificationV1
    ) {
        recordEncryptedEnvelopeLifecycle(classification)
    }
}

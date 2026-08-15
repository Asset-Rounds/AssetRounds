import Foundation

enum Counter: Sendable {
    case firstSignCreated
    case onboardingCompleted
    case paywallPresented
    case recheckCompleted
    case reportSaved
    case reportShareSheetPresented
}

enum PurchaseResult: Sendable {
    case cancelled
    case failed
    case pending
    case unverified
    case verified
}

struct PurchaseResultHistogram: Codable, Equatable, Sendable {
    var cancelled: Int64
    var failed: Int64
    var pending: Int64
    var unverified: Int64
    var verified: Int64

    static let zero = PurchaseResultHistogram(
        cancelled: 0,
        failed: 0,
        pending: 0,
        unverified: 0,
        verified: 0
    )
}

struct DiagnosticsV1: Codable, Equatable, Sendable {
    var firstSignCreated: Int64
    var onboardingCompleted: Int64
    var paywallPresented: Int64
    var purchaseResult: PurchaseResultHistogram
    var recheckCompleted: Int64
    var reportSaved: Int64
    var reportShareSheetPresented: Int64
    var schemaVersion: Int

    enum CodingKeys: String, CodingKey {
        case firstSignCreated = "first_sign_created"
        case onboardingCompleted = "onboarding_completed"
        case paywallPresented = "paywall_presented"
        case purchaseResult = "purchase_result"
        case recheckCompleted = "recheck_completed"
        case reportSaved = "report_saved"
        case reportShareSheetPresented = "report_share_sheet_presented"
        case schemaVersion
    }

    static let zero = DiagnosticsV1(
        firstSignCreated: 0,
        onboardingCompleted: 0,
        paywallPresented: 0,
        purchaseResult: .zero,
        recheckCompleted: 0,
        reportSaved: 0,
        reportShareSheetPresented: 0,
        schemaVersion: 1
    )

    var isValid: Bool {
        schemaVersion == 1
            && firstSignCreated >= 0
            && onboardingCompleted >= 0
            && paywallPresented >= 0
            && purchaseResult.cancelled >= 0
            && purchaseResult.failed >= 0
            && purchaseResult.pending >= 0
            && purchaseResult.unverified >= 0
            && purchaseResult.verified >= 0
            && recheckCompleted >= 0
            && reportSaved >= 0
            && reportShareSheetPresented >= 0
    }
}

actor DiagnosticsStore {
    private let directoryURL: URL
    private let countersURL: URL
    private let fileManager: FileManager
    private let logger: DiagnosticsLogger
    private var counters = DiagnosticsV1.zero
    private var isPrepared = false

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        logger: DiagnosticsLogger = .live
    ) {
        let directoryURL = applicationSupportURL.appendingPathComponent(
            "FieldEvidenceDiagnostics",
            isDirectory: true
        )
        self.directoryURL = directoryURL
        self.countersURL = directoryURL.appendingPathComponent(
            "counters.json",
            isDirectory: false
        )
        self.fileManager = fileManager
        self.logger = logger
    }

    func prepare() {
        guard !isPrepared else {
            return
        }
        isPrepared = true

        guard fileManager.fileExists(atPath: countersURL.path) else {
            _ = persist(.zero)
            return
        }

        do {
            let data = try Data(contentsOf: countersURL)
            let decoded = try JSONDecoder().decode(DiagnosticsV1.self, from: data)
            guard decoded.isValid, try canonicalData(for: decoded) == data else {
                throw DiagnosticsFailure.invalidFile
            }
            counters = decoded
        } catch {
            logger.record(.invalidCountersReset)
            _ = persist(.zero)
        }
    }

    func snapshot() -> DiagnosticsV1 {
        prepare()
        return counters
    }

    func acceptDescriptorErasedZero() {
        counters = .zero
        isPrepared = true
    }

    func isExactlyZero() -> Bool {
        prepare()
        return counters == .zero
    }

    func increment(_ counter: Counter) {
        prepare()
        var candidate = counters

        switch counter {
        case .firstSignCreated:
            candidate.firstSignCreated = incremented(candidate.firstSignCreated)
        case .onboardingCompleted:
            candidate.onboardingCompleted = incremented(candidate.onboardingCompleted)
        case .paywallPresented:
            candidate.paywallPresented = incremented(candidate.paywallPresented)
        case .recheckCompleted:
            candidate.recheckCompleted = incremented(candidate.recheckCompleted)
        case .reportSaved:
            candidate.reportSaved = incremented(candidate.reportSaved)
        case .reportShareSheetPresented:
            candidate.reportShareSheetPresented = incremented(
                candidate.reportShareSheetPresented
            )
        }

        if persist(candidate) {
            counters = candidate
        }
    }

    func incrementPurchaseResult(_ result: PurchaseResult) {
        prepare()
        var candidate = counters

        switch result {
        case .cancelled:
            candidate.purchaseResult.cancelled = incremented(
                candidate.purchaseResult.cancelled
            )
        case .failed:
            candidate.purchaseResult.failed = incremented(
                candidate.purchaseResult.failed
            )
        case .pending:
            candidate.purchaseResult.pending = incremented(
                candidate.purchaseResult.pending
            )
        case .unverified:
            candidate.purchaseResult.unverified = incremented(
                candidate.purchaseResult.unverified
            )
        case .verified:
            candidate.purchaseResult.verified = incremented(
                candidate.purchaseResult.verified
            )
        }

        if persist(candidate) {
            counters = candidate
        }
    }

    private func persist(_ candidate: DiagnosticsV1) -> Bool {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try canonicalData(for: candidate).write(to: countersURL, options: .atomic)
            return true
        } catch {
            logger.record(.countersWriteFailed)
            return false
        }
    }

    private func canonicalData(for value: DiagnosticsV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func incremented(_ value: Int64) -> Int64 {
        value == .max ? .max : value + 1
    }
}

private enum DiagnosticsFailure: Error {
    case invalidFile
}

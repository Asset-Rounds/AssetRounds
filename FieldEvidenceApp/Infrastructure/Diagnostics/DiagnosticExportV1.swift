import Foundation
import UIKit

struct DiagnosticAppContextV1: Codable, Equatable, Sendable {
    let build: String
    let version: String
}

struct DiagnosticDeviceContextV1: Codable, Equatable, Sendable {
    let model: String
    let osVersion: String
}

struct LaunchTimeMillisecondsV1: Codable, Equatable, Sendable {
    var from1000Through1999: Int64
    var from2000Up: Int64
    var from500Through999: Int64
    var under500: Int64

    static let zero = LaunchTimeMillisecondsV1(
        from1000Through1999: 0,
        from2000Up: 0,
        from500Through999: 0,
        under500: 0
    )

    var isValid: Bool {
        from1000Through1999 >= 0
            && from2000Up >= 0
            && from500Through999 >= 0
            && under500 >= 0
    }
}

struct MetricKitSummaryV1: Codable, Equatable, Sendable {
    let crashCount: Int64
    let hangCount: Int64
    let launchTimeMilliseconds: LaunchTimeMillisecondsV1?
    let peakMemoryBytes: Int64?

    var isValid: Bool {
        crashCount >= 0
            && hangCount >= 0
            && (launchTimeMilliseconds?.isValid ?? true)
            && (peakMemoryBytes.map { $0 >= 0 } ?? true)
    }
}

struct DiagnosticExportV1: Codable, Equatable, Sendable {
    let app: DiagnosticAppContextV1
    let counters: DiagnosticsV1
    let device: DiagnosticDeviceContextV1
    let diagnosticSchemaVersion: Int
    let generatedAt: Date
    let metricKit: MetricKitSummaryV1?

    var isValid: Bool {
        diagnosticSchemaVersion == 1
            && app.build.isDiagnosticSystemValue
            && app.version.isDiagnosticSystemValue
            && counters.isValid
            && device.model.isDiagnosticSystemValue
            && device.osVersion.isDiagnosticSystemValue
            && generatedAt.timeIntervalSinceReferenceDate.isFinite
            && (metricKit?.isValid ?? true)
    }
}

struct PreparedDiagnosticExportV1: Equatable, Sendable {
    let value: DiagnosticExportV1
    let canonicalData: Data
}

enum DiagnosticExportError: Error, Equatable {
    case invalidValue
}

struct DiagnosticExportService {
    typealias CountersProvider = () async -> DiagnosticsV1
    typealias MetricKitProvider = () -> MetricKitSummaryV1?
    typealias ContextProvider<Value> = () -> Value
    typealias Clock = () -> Date

    private let countersProvider: CountersProvider
    private let metricKitProvider: MetricKitProvider
    private let appProvider: ContextProvider<DiagnosticAppContextV1>
    private let deviceProvider: ContextProvider<DiagnosticDeviceContextV1>
    private let clock: Clock

    init(
        counters: @escaping CountersProvider,
        metricKit: @escaping MetricKitProvider,
        app: @escaping ContextProvider<DiagnosticAppContextV1>,
        device: @escaping ContextProvider<DiagnosticDeviceContextV1>,
        clock: @escaping Clock
    ) {
        countersProvider = counters
        metricKitProvider = metricKit
        appProvider = app
        deviceProvider = device
        self.clock = clock
    }

    @MainActor
    init(
        diagnosticsStore: DiagnosticsStore,
        metricKitAdapter: MetricKitDiagnosticsAdapter,
        bundle: Bundle = .main,
        device: UIDevice = .current,
        clock: @escaping Clock = Date.init
    ) {
        let app = DiagnosticAppContextV1(
            build: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "Unavailable",
            version: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "Unavailable"
        )
        let device = DiagnosticDeviceContextV1(
            model: device.model,
            osVersion: device.systemVersion
        )
        self.init(
            counters: { await diagnosticsStore.snapshot() },
            metricKit: { metricKitAdapter.snapshot() },
            app: { app },
            device: { device },
            clock: clock
        )
    }

    func prepare() async throws -> PreparedDiagnosticExportV1 {
        let value = DiagnosticExportV1(
            app: appProvider(),
            counters: await countersProvider(),
            device: deviceProvider(),
            diagnosticSchemaVersion: 1,
            generatedAt: clock(),
            metricKit: metricKitProvider()
        )
        guard value.isValid else {
            throw DiagnosticExportError.invalidValue
        }
        return PreparedDiagnosticExportV1(
            value: value,
            canonicalData: try DiagnosticExportCanonicalEncoderV1.encode(value)
        )
    }
}

enum DiagnosticExportCanonicalEncoderV1 {
    static func encode(_ value: DiagnosticExportV1) throws -> Data {
        guard value.isValid else {
            throw DiagnosticExportError.invalidValue
        }
        return try CanonicalJSONV1.encode(.object([
            "app": .object([
                "build": .string(value.app.build),
                "version": .string(value.app.version),
            ]),
            "counters": try counters(value.counters),
            "device": .object([
                "model": .string(value.device.model),
                "osVersion": .string(value.device.osVersion),
            ]),
            "diagnosticSchemaVersion": .integer(value.diagnosticSchemaVersion),
            "generatedAt": CanonicalJSONV1.date(value.generatedAt),
            "metricKit": try value.metricKit.map(metricKit) ?? .null,
        ]))
    }

    private static func counters(
        _ value: DiagnosticsV1
    ) throws -> CanonicalJSONValueV1 {
        .object([
            "first_sign_created": try integer(value.firstSignCreated),
            "onboarding_completed": try integer(value.onboardingCompleted),
            "paywall_presented": try integer(value.paywallPresented),
            "purchase_result": .object([
                "cancelled": try integer(value.purchaseResult.cancelled),
                "failed": try integer(value.purchaseResult.failed),
                "pending": try integer(value.purchaseResult.pending),
                "unverified": try integer(value.purchaseResult.unverified),
                "verified": try integer(value.purchaseResult.verified),
            ]),
            "recheck_completed": try integer(value.recheckCompleted),
            "report_saved": try integer(value.reportSaved),
            "report_share_sheet_presented": try integer(
                value.reportShareSheetPresented
            ),
            "schemaVersion": .integer(value.schemaVersion),
        ])
    }

    private static func metricKit(
        _ value: MetricKitSummaryV1
    ) throws -> CanonicalJSONValueV1 {
        .object([
            "crashCount": try integer(value.crashCount),
            "hangCount": try integer(value.hangCount),
            "launchTimeMilliseconds": try value.launchTimeMilliseconds.map(
                launchTime
            ) ?? .null,
            "peakMemoryBytes": try value.peakMemoryBytes.map(integer) ?? .null,
        ])
    }

    private static func launchTime(
        _ value: LaunchTimeMillisecondsV1
    ) throws -> CanonicalJSONValueV1 {
        .object([
            "from1000Through1999": try integer(value.from1000Through1999),
            "from2000Up": try integer(value.from2000Up),
            "from500Through999": try integer(value.from500Through999),
            "under500": try integer(value.under500),
        ])
    }

    private static func integer(_ value: Int64) throws -> CanonicalJSONValueV1 {
        guard let exact = Int(exactly: value) else {
            throw DiagnosticExportError.invalidValue
        }
        return .integer(exact)
    }
}

private extension String {
    var isDiagnosticSystemValue: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return self == trimmed
            && !trimmed.isEmpty
            && trimmed.count <= 128
            && !unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

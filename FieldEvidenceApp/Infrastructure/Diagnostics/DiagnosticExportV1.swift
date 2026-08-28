import CryptoKit
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

/// A bounded, privacy-safe summary of WorkPacket coordination. It carries
/// counts only: packet/item identifiers, actors, claim/lease payloads,
/// evidence, and result content never enter a diagnostic export.
struct WorkPacketDiagnosticSummaryV1: Codable, Equatable, Sendable {
    let packetCount: Int
    let itemCount: Int
    let claimedItemCount: Int
    let leasedItemCount: Int
    let releasedItemCount: Int
    let handedOffItemCount: Int
    let collisionCount: Int

    var isValid: Bool {
        let values = [
            packetCount,
            itemCount,
            claimedItemCount,
            leasedItemCount,
            releasedItemCount,
            handedOffItemCount,
            collisionCount,
        ]
        return values.allSatisfy { $0 >= 0 }
            && claimedItemCount <= itemCount
            && leasedItemCount <= itemCount
            && releasedItemCount <= itemCount
            && handedOffItemCount <= itemCount
            && collisionCount <= itemCount
    }
}

struct DiagnosticExportV1: Codable, Equatable, Sendable {
    let app: DiagnosticAppContextV1
    let counters: DiagnosticsV1
    let device: DiagnosticDeviceContextV1
    let diagnosticSchemaVersion: Int
    let generatedAt: Date
    let metricKit: MetricKitSummaryV1?
    /// Optional frozen assurance evidence.  The default remains nil until the
    /// owning production finalization surface is activated.
    var requirementAssurance: RequirementAssuranceSnapshotV1? = nil
    /// Optional WorkPacket coordination counts. This is deliberately a
    /// summary-only surface and is absent unless the caller supplies it.
    var workPacket: WorkPacketDiagnosticSummaryV1? = nil
    /// Optional C19 metadata-only summary. Exact values, units, actor
    /// snapshots, opaque serials, and evidence references are never diagnostic
    /// payload and therefore do not appear here.
    var measurementIntegrity: MeasurementIntegrityDiagnosticMetadataV1? = nil
    /// Optional C20 metadata-only privacy-transform health summary. It carries
    /// counts and denial states, never content bytes, content identifiers,
    /// review rationale, or reviewer identity.
    var privacyTransform: PrivacyTransformDiagnosticMetadataV1? = nil

    /// Integration event payloads, subjects, cursors, and checkpoint bytes are
    /// never diagnostic material. Diagnostics may describe only the static
    /// drop-and-rebuild posture through code-owned policy.
    var integrationProjectionPayloadExcluded: Bool {
        IntegrationProjectionSchemaV1.persistenceMode == "DERIVED_ONLY"
            && !IntegrationProjectionSchemaV1.canonicalExportIncluded
            && !IntegrationProjectionSchemaV1.canonicalReportSource
    }

    var isValid: Bool {
        diagnosticSchemaVersion == 1
            && app.build.isDiagnosticSystemValue
            && app.version.isDiagnosticSystemValue
            && counters.isValid
            && device.model.isDiagnosticSystemValue
            && device.osVersion.isDiagnosticSystemValue
            && generatedAt.timeIntervalSinceReferenceDate.isFinite
            && (metricKit?.isValid ?? true)
            && (requirementAssurance.map {
                RequirementAssuranceSnapshotCanonicalCodecV1.isValid($0)
            } ?? true)
            && (workPacket?.isValid ?? true)
            && (measurementIntegrity?.isValid ?? true)
            && (privacyTransform?.isValid ?? true)
            && integrationProjectionPayloadExcluded
    }

    var requirementExplanations: [RequirementExplanationItemV1] {
        requirementAssurance.map {
            RequirementExplanationProjectionV1.project($0.evaluations)
        } ?? []
    }
}

struct PreparedDiagnosticExportV1: Equatable, Sendable {
    let value: DiagnosticExportV1
    let canonicalData: Data
}

enum DiagnosticExportError: Error, Equatable {
    case invalidValue
}

enum IntegrationProjectionDiagnosticExclusionV1 {
    static let forbiddenJSONKeys = [
        "checkpointSHA256", "consumerStateSHA256", "eventID",
        "eventSHA256", "lastEventID", "lastEventSHA256", "payloadSHA256",
        "sourceReceiptSHA256", "subjectSemanticSHA256",
    ]

    static func validate(_ data: Data) throws {
        guard IntegrationProjectionSchemaV1.persistenceMode == "DERIVED_ONLY",
              !IntegrationProjectionSchemaV1.canonicalExportIncluded,
              forbiddenJSONKeys.allSatisfy({ key in
                  data.range(of: Data("\"\(key)\"".utf8)) == nil
              }) else { throw DiagnosticExportError.invalidValue }
    }
}

struct DiagnosticExportService {
    typealias CountersProvider = () async -> DiagnosticsV1
    typealias MetricKitProvider = () -> MetricKitSummaryV1?
    typealias RequirementAssuranceProvider = () -> RequirementAssuranceSnapshotV1?
    typealias WorkPacketProvider = () -> WorkPacketDiagnosticSummaryV1?
    typealias ContextProvider<Value> = () -> Value
    typealias Clock = () -> Date

    private let countersProvider: CountersProvider
    private let metricKitProvider: MetricKitProvider
    private let requirementAssuranceProvider: RequirementAssuranceProvider
    private let workPacketProvider: WorkPacketProvider
    private let appProvider: ContextProvider<DiagnosticAppContextV1>
    private let deviceProvider: ContextProvider<DiagnosticDeviceContextV1>
    private let clock: Clock

    init(
        counters: @escaping CountersProvider,
        metricKit: @escaping MetricKitProvider,
        app: @escaping ContextProvider<DiagnosticAppContextV1>,
        device: @escaping ContextProvider<DiagnosticDeviceContextV1>,
        clock: @escaping Clock,
        requirementAssurance: @escaping RequirementAssuranceProvider = { nil },
        workPacket: @escaping WorkPacketProvider = { nil }
    ) {
        countersProvider = counters
        metricKitProvider = metricKit
        requirementAssuranceProvider = requirementAssurance
        workPacketProvider = workPacket
        appProvider = app
        deviceProvider = device
        self.clock = clock
    }

    @MainActor
    init(
        diagnosticsStore: DiagnosticsStore,
        metricKitAdapter: MetricKitDiagnosticsAdapter,
        requirementAssurance: @escaping RequirementAssuranceProvider = { nil },
        workPacket: @escaping WorkPacketProvider = { nil },
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
            clock: clock,
            requirementAssurance: requirementAssurance,
            workPacket: workPacket
        )
    }

    func prepare() async throws -> PreparedDiagnosticExportV1 {
        let value = DiagnosticExportV1(
            app: appProvider(),
            counters: await countersProvider(),
            device: deviceProvider(),
            diagnosticSchemaVersion: 1,
            generatedAt: clock(),
            metricKit: metricKitProvider(),
            requirementAssurance: requirementAssuranceProvider(),
            workPacket: workPacketProvider()
        )
        guard value.isValid else {
            throw DiagnosticExportError.invalidValue
        }
        let canonicalData = try DiagnosticExportCanonicalEncoderV1.encode(value)
        try IntegrationProjectionDiagnosticExclusionV1.validate(canonicalData)
        return PreparedDiagnosticExportV1(value: value, canonicalData: canonicalData)
    }
}

enum DiagnosticExportCanonicalEncoderV1 {
    static func encode(_ value: DiagnosticExportV1) throws -> Data {
        guard value.isValid else {
            throw DiagnosticExportError.invalidValue
        }
        var object: [String: CanonicalJSONValueV1] = [
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
        ]
        if let assurance = value.requirementAssurance {
            object["requirementAssurance"] = CanonicalJSONV1.requirementAssurance(assurance)
        }
        if let workPacket = value.workPacket {
            object["workPacket"] = workPacketValue(workPacket)
        }
        if let measurementIntegrity = value.measurementIntegrity {
            object["measurementIntegrity"] = measurementIntegrityValue(measurementIntegrity)
        }
        if let privacyTransform = value.privacyTransform {
            object["privacyTransform"] = privacyTransformValue(privacyTransform)
        }
        let data = try CanonicalJSONV1.encode(.object(object))
        try IntegrationProjectionDiagnosticExclusionV1.validate(data)
        return data
    }

    private static func workPacketValue(
        _ value: WorkPacketDiagnosticSummaryV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "claimedItemCount": .integer(value.claimedItemCount),
            "collisionCount": .integer(value.collisionCount),
            "handedOffItemCount": .integer(value.handedOffItemCount),
            "itemCount": .integer(value.itemCount),
            "leasedItemCount": .integer(value.leasedItemCount),
            "packetCount": .integer(value.packetCount),
            "releasedItemCount": .integer(value.releasedItemCount),
        ])
    }

    private static func measurementIntegrityValue(
        _ value: MeasurementIntegrityDiagnosticMetadataV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "captureCount": .integer(value.captureCount),
            "seriesCount": .integer(value.seriesCount),
            "qualityAssessmentCount": .integer(value.qualityAssessmentCount),
            "calibrationStatuses": .array(value.calibrationStatuses.map { .string($0.rawValue) }),
            "qualityResults": .array(value.qualityResults.map { .string($0.rawValue) }),
            "sourceModes": .array(value.sourceModes.map { .string($0.rawValue) }),
            "policyVersion": .string(value.policyVersion),
            "metadataOnly": .bool(value.metadataOnly),
            "excludesCanonicalValues": .bool(value.excludesCanonicalValues),
            "excludesOpaqueSerials": .bool(value.excludesOpaqueSerials),
            "excludesOperatorIdentity": .bool(value.excludesOperatorIdentity),
            "excludesEvidenceLocators": .bool(value.excludesEvidenceLocators),
        ])
    }

    private static func privacyTransformValue(
        _ value: PrivacyTransformDiagnosticMetadataV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "schemaVersion": .integer(value.schemaVersion),
            "manifestCount": .integer(value.manifestCount),
            "approvedDerivativeCount": .integer(value.approvedDerivativeCount),
            "deniedProjectionCount": .integer(value.deniedProjectionCount),
            "denialStates": .array(value.denialStates.map { .string($0.rawValue) }),
            "redactionDeclarationsCount": .integer(value.redactionDeclarationsCount),
            "policyVersion": .string(value.policyVersion),
            "metadataOnly": .bool(value.metadataOnly),
            "excludesDerivativeBytes": .bool(value.excludesDerivativeBytes),
            "excludesOriginalBytes": .bool(value.excludesOriginalBytes),
            "excludesReviewRationale": .bool(value.excludesReviewRationale),
            "excludesReviewerIdentity": .bool(value.excludesReviewerIdentity),
            "excludesSourceContentIdentifiers": .bool(value.excludesSourceContentIdentifiers),
        ])
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

enum SupportBundleBuilderFailureV1: Error, Equatable, Sendable {
    case alreadyFinished
    case cancelled
    case cleanupFailed
    case invalidSource
    case sizeLimitExceeded
    case writeFailed
}

struct SupportExportCancellationV1: Sendable {
    static let never = SupportExportCancellationV1 { false }
    private let source: @Sendable () -> Bool

    init(_ source: @escaping @Sendable () -> Bool) {
        self.source = source
    }

    var isCancelled: Bool { source() }
}

private struct SupportBundlePayloadV1: Codable {
    let manifest: SupportBundleManifestV1
    let members: [String: Data]
}

/// Builds one explicit, local-only support artifact from an allowlist. It has
/// no uploader, network client, customer identifier, work payload, or raw-log
/// input. The caller owns presentation of the share sheet and must finish with
/// the explicit external-effect disposition after sharing or cancellation.
struct SupportBundleBuilderV1: Sendable {
    typealias DiagnosticProvider = @Sendable () async throws -> PreparedDiagnosticExportV1
    typealias SupportProvider = @Sendable () async throws -> DeviceOperationalSupportSnapshotV2
    typealias Clock = @Sendable () -> Date
    typealias IDSource = @Sendable () -> UUID

    private let diagnosticProvider: DiagnosticProvider
    private let supportProvider: SupportProvider
    private let scratch: any ScratchDataLeasePortV1
    private let clock: Clock
    private let idSource: IDSource

    init(
        diagnostic: @escaping DiagnosticProvider,
        support: @escaping SupportProvider,
        scratch: any ScratchDataLeasePortV1,
        clock: @escaping Clock,
        idSource: @escaping IDSource
    ) {
        diagnosticProvider = diagnostic
        supportProvider = support
        self.scratch = scratch
        self.clock = clock
        self.idSource = idSource
    }

    func prepare(
        mode: SupportBundleModeV1,
        cancellation: SupportExportCancellationV1 = .never
    ) async throws -> SupportExportResultV1 {
        if cancellation.isCancelled {
            return try SupportExportResultV1(
                disposition: .cancelled,
                manifest: nil,
                lease: nil,
                fileURL: nil
            )
        }
        let diagnostic: PreparedDiagnosticExportV1
        do {
            diagnostic = try await diagnosticProvider()
            guard diagnostic.canonicalData.count
                    <= SupportBundleManifestV1.maximumCanonicalBytes else {
                throw SupportBundleBuilderFailureV1.sizeLimitExceeded
            }
            guard diagnostic.value.isValid,
                  try DiagnosticExportCanonicalEncoderV1.encode(
                      diagnostic.value
                  ) == diagnostic.canonicalData else {
                throw SupportBundleBuilderFailureV1.invalidSource
            }
        } catch let failure as SupportBundleBuilderFailureV1 {
            throw failure
        } catch {
            throw SupportBundleBuilderFailureV1.invalidSource
        }
        var members: [(SupportBundleMemberKindV1, String, Data)] = [
            (.diagnosticSummary, "diagnostic-summary.json", diagnostic.canonicalData)
        ]
        if mode == .full {
            do {
                let snapshot = try await supportProvider()
                try snapshot.health.validate()
                guard snapshot.counters.isValid else {
                    throw SupportBundleBuilderFailureV1.invalidSource
                }
                members.append((
                    .systemHealth,
                    "system-health.json",
                    try Self.encodeCanonical(snapshot)
                ))
            } catch let failure as SupportBundleBuilderFailureV1 {
                throw failure
            } catch {
                throw SupportBundleBuilderFailureV1.invalidSource
            }
        }
        if cancellation.isCancelled {
            return try SupportExportResultV1(
                disposition: .cancelled,
                manifest: nil,
                lease: nil,
                fileURL: nil
            )
        }
        let total = try members.reduce(0) { partial, member in
            let (next, overflow) = partial.addingReportingOverflow(member.2.count)
            guard !overflow, next <= SupportBundleManifestV1.maximumCanonicalBytes else {
                throw SupportBundleBuilderFailureV1.sizeLimitExceeded
            }
            return next
        }
        let generatedAt = clock()
        let bundleID = idSource()
        let entries = members.map { member in
            SupportBundleManifestEntryV1(
                kind: member.0,
                relativeName: member.1,
                byteCount: member.2.count,
                sha256: Self.sha256(member.2)
            )
        }
        let manifest = try SupportBundleManifestV1(
            bundleID: bundleID,
            mode: mode,
            generatedAt: generatedAt,
            entries: entries,
            totalCanonicalByteCount: total
        )
        let payload = try Self.encodeCanonical(SupportBundlePayloadV1(
            manifest: manifest,
            members: Dictionary(uniqueKeysWithValues: members.map { ($0.1, $0.2) })
        ))
        guard payload.count <= SupportBundleManifestV1.maximumCanonicalBytes else {
            throw SupportBundleBuilderFailureV1.sizeLimitExceeded
        }
        let lease = try await scratch.acquireScratchLease(
            try ScratchDataLeaseRequestV1(
                leaseID: idSource(),
                purpose: .supportExport,
                owner: .supportExport,
                ownerOperationID: bundleID,
                requestedByteCount: UInt64(SupportBundleManifestV1.maximumCanonicalBytes),
                createdAt: generatedAt,
                expiresAt: generatedAt.addingTimeInterval(
                    ScratchDataPurposeV1.supportExport.maximumLifetimeSeconds
                )
            )
        )
        if cancellation.isCancelled {
            try await release(lease, terminal: .cancelled)
            return try SupportExportResultV1(
                disposition: .cancelled,
                manifest: nil,
                lease: nil,
                fileURL: nil
            )
        }
        do {
            let url = try await scratch.writeScratchData(
                payload,
                named: "support-bundle.json",
                lease: lease
            )
            return try SupportExportResultV1(
                disposition: .prepared,
                manifest: manifest,
                lease: lease,
                fileURL: url
            )
        } catch {
            try await release(lease, terminal: .failed)
            throw SupportBundleBuilderFailureV1.writeFailed
        }
    }

    /// Called only after the caller knows whether the external share effect
    /// occurred. The returned closed receipt never claims sharing early.
    func finish(
        _ result: SupportExportResultV1,
        disposition: SupportExportDispositionV1
    ) async throws -> SupportExportResultV1 {
        guard result.disposition == .prepared, let lease = result.lease else {
            throw SupportBundleBuilderFailureV1.invalidSource
        }
        let terminal: ScratchDataLeaseTerminalV1
        switch disposition {
        case .shared: terminal = .completed
        case .cancelled: terminal = .cancelled
        case .failed: terminal = .failed
        case .expired: terminal = .recoveredExpired
        case .prepared:
            throw SupportBundleBuilderFailureV1.invalidSource
        }
        guard result.manifest != nil else {
            throw SupportBundleBuilderFailureV1.invalidSource
        }
        let receipt = try SupportExportResultV1(
            disposition: disposition,
            manifest: disposition == .shared ? result.manifest : nil,
            lease: nil,
            fileURL: nil
        )
        guard result.beginTerminalDisposition(disposition) else {
            throw SupportBundleBuilderFailureV1.alreadyFinished
        }
        do {
            try await release(lease, terminal: terminal)
        } catch {
            result.rollbackTerminalDisposition(disposition)
            throw error
        }
        result.commitTerminalDisposition(disposition)
        return receipt
    }

    private func release(
        _ lease: ScratchDataLeaseV1,
        terminal: ScratchDataLeaseTerminalV1
    ) async throws {
        do {
            try await scratch.releaseScratchLease(lease, terminal: terminal)
        } catch {
            throw SupportBundleBuilderFailureV1.cleanupFailed
        }
    }

    private static func encodeCanonical<Value: Encodable>(
        _ value: Value
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Metadata-only C18 diagnostics. No package bytes, draft payload, actor
/// identity, exact candidate head, or receipt digest is diagnostic material.
struct PackageEvolutionDiagnosticMetadataV1: Codable, Equatable, Sendable {
    let packageID: String
    let packageReleaseID: String
    let semanticClassification: PackageSemanticDiffClassificationV1
    let promotionStatus: PackageEvolutionConsumerStatusV1

    init(metadata: PackageEvolutionConsumerMetadataV1) throws {
        try metadata.validate()
        packageID = metadata.packageID
        packageReleaseID = metadata.packageReleaseID
        semanticClassification = metadata.semanticClassification
        promotionStatus = metadata.promotionStatus
        try validate()
    }

    init(bundle: PackagePromotionAtomicBundleV1) throws {
        try self.init(metadata: PackageEvolutionConsumerMetadataV1(bundle: bundle))
    }

    func validate() throws {
        guard InspectionPackageValidationV2.validIdentifier(packageID, maximumBytes: 200),
              KernelCanonicalHashV1.validSHA256(packageReleaseID) else {
            throw PackageEvolutionConsumerFailureV1.invalidMetadata
        }
    }

    static let includesCanonicalPackageBytes = false
    static let includesDraftPayload = false
    static let includesActorIdentity = false
    static let includesExactCandidateHead = false
}

extension DiagnosticExportV1 {
    static func packageEvolutionDiagnosticMetadata(
        _ metadata: PackageEvolutionConsumerMetadataV1
    ) throws -> PackageEvolutionDiagnosticMetadataV1 {
        try PackageEvolutionDiagnosticMetadataV1(metadata: metadata)
    }

    static func packageEvolutionDiagnosticMetadata(
        _ bundle: PackagePromotionAtomicBundleV1
    ) throws -> PackageEvolutionDiagnosticMetadataV1 {
        try PackageEvolutionDiagnosticMetadataV1(bundle: bundle)
    }
}

/// The diagnostic surface for C19 is intentionally a bounded health summary.
/// It can report counts and recorded dispositions, but never values, units,
/// operator identity, serials, response payloads, or evidence locators.
struct MeasurementIntegrityDiagnosticMetadataV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let policyVersion = "MEASUREMENT_INTEGRITY_DIAGNOSTIC_V1"

    let schemaVersion: Int
    let captureCount: Int
    let seriesCount: Int
    let qualityAssessmentCount: Int
    let calibrationStatuses: [CalibrationStatusV1]
    let qualityResults: [MeasurementQualityResultV1]
    let sourceModes: [MeasurementCaptureSourceModeV1]
    let policyVersion: String
    let metadataOnly: Bool
    let excludesCanonicalValues: Bool
    let excludesOpaqueSerials: Bool
    let excludesOperatorIdentity: Bool
    let excludesEvidenceLocators: Bool

    init(
        captures: [MeasurementCaptureV1],
        series: [MeasurementSeriesV1] = [],
        qualityAssessments: [MeasurementQualityAssessmentV1] = [],
        calibrationStatuses: [CalibrationStatusV1] = []
    ) throws {
        try captures.forEach { try $0.validate() }
        try series.forEach { try $0.validate() }
        try qualityAssessments.forEach { try $0.validate() }
        guard captures.count <= MeasurementIntegrityLimitsV1.maximumSampleCount,
              series.count <= MeasurementIntegrityLimitsV1.maximumSampleCount,
              qualityAssessments.count <= MeasurementIntegrityLimitsV1.maximumSampleCount else {
            throw DiagnosticExportError.invalidValue
        }
        schemaVersion = Self.schemaVersion
        captureCount = captures.count
        seriesCount = series.count
        qualityAssessmentCount = qualityAssessments.count
        self.calibrationStatuses = Array(Set(calibrationStatuses.map(\.rawValue)))
            .compactMap(CalibrationStatusV1.init(rawValue:))
            .sorted { $0.rawValue < $1.rawValue }
        qualityResults = Array(Set(qualityAssessments.map { $0.result.rawValue }))
            .compactMap(MeasurementQualityResultV1.init(rawValue:))
            .sorted { $0.rawValue < $1.rawValue }
        sourceModes = Array(Set(captures.map { $0.sourceMode.rawValue }))
            .compactMap(MeasurementCaptureSourceModeV1.init(rawValue:))
            .sorted { $0.rawValue < $1.rawValue }
        policyVersion = Self.policyVersion
        metadataOnly = true
        excludesCanonicalValues = true
        excludesOpaqueSerials = true
        excludesOperatorIdentity = true
        excludesEvidenceLocators = true
        try validate()
    }

    var isValid: Bool {
        (try? validate()) != nil
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              captureCount >= 0, seriesCount >= 0, qualityAssessmentCount >= 0,
              calibrationStatuses == calibrationStatuses.sorted(by: { $0.rawValue < $1.rawValue }),
              qualityResults == qualityResults.sorted(by: { $0.rawValue < $1.rawValue }),
              sourceModes == sourceModes.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(calibrationStatuses.map(\.rawValue)).count == calibrationStatuses.count,
              Set(qualityResults.map(\.rawValue)).count == qualityResults.count,
              Set(sourceModes.map(\.rawValue)).count == sourceModes.count,
              policyVersion == Self.policyVersion,
              metadataOnly, excludesCanonicalValues, excludesOpaqueSerials,
              excludesOperatorIdentity, excludesEvidenceLocators else {
            throw DiagnosticExportError.invalidValue
        }
    }
}

/// C20 diagnostics contain only bounded projection health facts. No content
/// identifier, digest, byte payload, actor identity, or review rationale is
/// retained in this type.
struct PrivacyTransformDiagnosticMetadataV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let policyVersion = "PRIVACY_TRANSFORM_DIAGNOSTIC_V1"

    let schemaVersion: Int
    let manifestCount: Int
    let approvedDerivativeCount: Int
    let deniedProjectionCount: Int
    let denialStates: [PrivacyProjectionDenialV1]
    let redactionDeclarationsCount: Int
    let policyVersion: String
    let metadataOnly: Bool
    let excludesDerivativeBytes: Bool
    let excludesOriginalBytes: Bool
    let excludesReviewRationale: Bool
    let excludesReviewerIdentity: Bool
    let excludesSourceContentIdentifiers: Bool

    init(
        approvedProjections: [PrivacyTransformReportProjectionV1] = [],
        deniedProjectionStates: [PrivacyProjectionDenialV1] = [],
        manifestCount: Int? = nil
    ) throws {
        for projection in approvedProjections {
            try projection.validate()
        }
        let orderedDenials = deniedProjectionStates.sorted { $0.rawValue < $1.rawValue }
        guard Set(orderedDenials).count == orderedDenials.count,
              orderedDenials == Array(Set(orderedDenials)).sorted(by: { $0.rawValue < $1.rawValue }),
              approvedProjections.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              deniedProjectionStates.count <= SnapshotProjectionLimitsV1.maximumHistoryFacts,
              (manifestCount ?? approvedProjections.count) >= approvedProjections.count else {
            throw DiagnosticExportError.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.manifestCount = manifestCount ?? approvedProjections.count
        approvedDerivativeCount = approvedProjections.count
        deniedProjectionCount = deniedProjectionStates.count
        denialStates = orderedDenials
        redactionDeclarationsCount = approvedProjections.count
        policyVersion = Self.policyVersion
        metadataOnly = true
        excludesDerivativeBytes = true
        excludesOriginalBytes = true
        excludesReviewRationale = true
        excludesReviewerIdentity = true
        excludesSourceContentIdentifiers = true
        try validate()
    }

    var isValid: Bool { (try? validate()) != nil }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              manifestCount >= approvedDerivativeCount,
              approvedDerivativeCount >= 0,
              deniedProjectionCount >= 0,
              redactionDeclarationsCount == approvedDerivativeCount,
              denialStates == denialStates.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(denialStates).count == denialStates.count,
              policyVersion == Self.policyVersion,
              metadataOnly,
              excludesDerivativeBytes,
              excludesOriginalBytes,
              excludesReviewRationale,
              excludesReviewerIdentity,
              excludesSourceContentIdentifiers else {
            throw DiagnosticExportError.invalidValue
        }
    }
}

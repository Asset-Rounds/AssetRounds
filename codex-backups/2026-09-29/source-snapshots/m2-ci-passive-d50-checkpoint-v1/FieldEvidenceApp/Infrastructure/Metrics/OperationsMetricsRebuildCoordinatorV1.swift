import Foundation

enum OperationsMetricsRebuildFailureV1: Error, Equatable, Sendable {
    case invalidSource
    case duplicateSource
    case staleContinuation
    case cancelled
    case corruptDerivedProjection
    case scaleLimitExceeded
}

/// A read-only snapshot of the C53 canonical event families needed to derive a
/// single asset's operations dashboard.  This is deliberately a value passed
/// into the rebuild operation: it is not a cache, store row, or lifecycle
/// record, and C09 never writes any of its events.
struct OperationsMetricsCanonicalSourceV1: Sendable {
    static let maximumAssetsPerRebuild = 10_000

    let workspaceID: WorkspaceID
    let subject: ServiceReliabilitySubjectV1
    let observationWindow: ServiceReliabilityClosedIntervalV1
    let asOf: ServiceReliabilityInstantV1
    let incidents: [AssetServiceIncidentV1]
    let exposures: [QualifiedServiceExposureV1]
    let segments: [ServiceImpactSegmentV1]
    let repairs: [ServiceRepairIntervalV1]
    let restorations: [ServiceRestorationAssertionV1]
    let placementEvents: [AssetPoseEventV1]
    let supplementalEvents: [AssetServiceHistorySupplementalCanonicalEventV1]

    init(
        workspaceID: WorkspaceID,
        subject: ServiceReliabilitySubjectV1,
        observationWindow: ServiceReliabilityClosedIntervalV1,
        asOf: ServiceReliabilityInstantV1,
        incidents: [AssetServiceIncidentV1],
        exposures: [QualifiedServiceExposureV1],
        segments: [ServiceImpactSegmentV1],
        repairs: [ServiceRepairIntervalV1],
        restorations: [ServiceRestorationAssertionV1],
        placementEvents: [AssetPoseEventV1] = [],
        supplementalEvents: [AssetServiceHistorySupplementalCanonicalEventV1] = []
    ) throws {
        self.workspaceID = workspaceID
        self.subject = subject
        self.observationWindow = observationWindow
        self.asOf = asOf
        self.incidents = incidents
        self.exposures = exposures
        self.segments = segments
        self.repairs = repairs
        self.restorations = restorations
        self.placementEvents = placementEvents
        self.supplementalEvents = supplementalEvents
        try validate()
    }

    func validate() throws {
        try subject.validate()
        try observationWindow.validate()
        try asOf.validate()
        try incidents.forEach { try $0.validate() }
        try exposures.forEach { try $0.validate() }
        try segments.forEach { try $0.validate() }
        try repairs.forEach { try $0.validate() }
        try restorations.forEach { try $0.validate() }
        try placementEvents.forEach { try $0.validateIntrinsic() }
        try supplementalEvents.forEach { try $0.validate() }
        guard subject.frozenScope.workspaceID == workspaceID,
              incidents.count <= ServiceReliabilityLimitsV1.maximumIntervals,
              exposures.count <= ServiceReliabilityLimitsV1.maximumIntervals,
              segments.count <= ServiceReliabilityLimitsV1.maximumIntervals,
              repairs.count <= ServiceReliabilityLimitsV1.maximumIntervals,
              restorations.count <= ServiceReliabilityLimitsV1.maximumIntervals,
              placementEvents.count <= ServiceReliabilityLimitsV1.maximumIntervals,
              supplementalEvents.count <= ServiceReliabilityLimitsV1.maximumIntervals,
              incidents.allSatisfy({ $0.workspaceID == workspaceID && $0.subject == subject }),
              placementEvents.allSatisfy({
                  $0.workspaceID == workspaceID && $0.assetID == subject.asset.subjectID
              }),
              supplementalEvents.allSatisfy({
                  $0.workspaceID == workspaceID && $0.assetID == subject.asset.subjectID
              })
        else { throw OperationsMetricsRebuildFailureV1.invalidSource }
    }

    fileprivate var stableIdentity: String {
        [
            workspaceID.rawValue.uuidString.lowercased(),
            subject.asset.subjectID.uuidString.lowercased(),
            subject.reliabilityIdentityEpochID.uuidString.lowercased(),
            String(observationWindow.lowerBound.millisecondsSince1970),
            String(observationWindow.upperBound.millisecondsSince1970),
            String(asOf.millisecondsSince1970)
        ].joined(separator: "|")
    }

    /// The complete canonical closure for every value that can influence a
    /// C09 projection, including the C53-only inputs and the timeline-only
    /// canonical event families.  This is deliberately distinct from C53's
    /// `ReliabilityMetricInputProjectionV1.projectionSHA256`.
    func canonicalSourceClosureSHA256() throws -> String {
        try validate()
        return try ServiceReliabilityCanonicalCodecV1.sha256(
            OperationsMetricsCanonicalSourceClosureV1(self)
        )
    }
}

/// A caller-held continuation is valid only for the exact sorted source set.
/// It is never persisted and therefore cannot create a second lifecycle or
/// receipt path.  Restarting from zero is always safe after process loss.
struct OperationsMetricsRebuildContinuationV1: Codable, Equatable, Sendable {
    let sourceSetSHA256: String
    let nextSourceIndex: Int

    init(sourceSetSHA256: String, nextSourceIndex: Int) throws {
        try ServiceReliabilityLimitsV1.digest(sourceSetSHA256)
        guard nextSourceIndex >= 0 else { throw OperationsMetricsRebuildFailureV1.staleContinuation }
        self.sourceSetSHA256 = sourceSetSHA256
        self.nextSourceIndex = nextSourceIndex
    }
}

/// The report and open-JSON values are handoffs to existing report/export
/// consumers.  They are regenerated from C53 inputs on every invocation and
/// are intentionally retained only by the caller.
struct OperationsMetricsDerivedProjectionV1: Equatable, Sendable {
    let dashboard: DashboardProjectionV1
    let timeline: AssetServiceHistoryTimelineV1
    let reportProjection: C53ServiceReliabilityReportProjectionV1
    let reportEnvelopes: [OperationsMetricsReportEnvelopeV1]
    let openJSON: Data
    let canonicalSourceClosureSHA256: String

    func validate() throws {
        try dashboard.validate()
        try timeline.validate()
        try C53ServiceReliabilityReportProjectionRegistryV1.validate(reportProjection)
        try reportEnvelopes.forEach { try $0.validate() }
        try ServiceReliabilityLimitsV1.digest(canonicalSourceClosureSHA256)
        let openJSONPayload = try ServiceReliabilityCanonicalCodecV1.decode(
            OperationsMetricsOpenJSONPayloadV1.self,
            from: openJSON
        )
        let c53InputProjectionSHA256 = reportProjection.sourceProjectionSHA256
        guard openJSONPayload.canonicalSourceClosureSHA256 == canonicalSourceClosureSHA256,
              timeline.workspaceID == dashboard.workspaceID,
              timeline.subject == dashboard.subject,
              reportEnvelopes.map(\.projection) == dashboard.metricProjections,
              reportEnvelopes.map(\.metricDefinitionID) == OperationsMetricDefinitionIDV1.allCases,
              openJSONPayload.dashboard == dashboard,
              openJSONPayload.timeline == timeline,
              openJSONPayload.reportEnvelopes == reportEnvelopes,
              dashboard.metricProjections.allSatisfy({
                  $0.inputProjectionSHA256 == c53InputProjectionSHA256
              })
        else { throw OperationsMetricsRebuildFailureV1.corruptDerivedProjection }
    }

    /// C53's narrower metric-input digest remains available independently of
    /// the full C09 canonical source closure.
    var c53InputProjectionSHA256: String {
        reportProjection.sourceProjectionSHA256
    }
}

struct OperationsMetricsRebuildResultV1: Equatable, Sendable {
    let projections: [OperationsMetricsDerivedProjectionV1]
    let continuation: OperationsMetricsRebuildContinuationV1?
}

/// Deterministic, nonpersistent rebuilding of C09 views.  There is no cache
/// to trust after a failure: corrupt or interrupted derived output is dropped
/// by the caller and reconstructed from the same canonical C53 events.
actor OperationsMetricsRebuildCoordinatorV1 {
    static let schema = OperationsMetricsContractV1.schema
    static let persistenceMode = OperationsMetricsContractV1.persistenceMode
    static let downgradeDisposition = OperationsMetricsContractV1.dropAndRebuildDisposition
    static let ownsCanonicalPersistence = false
    static let ownsBackupRestore = false
    static let ownsDeleteOrErase = false
    static let createsMutationReceipt = false

    func rebuild(
        sources: [OperationsMetricsCanonicalSourceV1],
        continuation: OperationsMetricsRebuildContinuationV1? = nil,
        maximumOutputs: Int? = nil
    ) async throws -> OperationsMetricsRebuildResultV1 {
        try OperationsMetricsContractV1.validateRegistry()
        guard sources.count <= OperationsMetricsCanonicalSourceV1.maximumAssetsPerRebuild,
              maximumOutputs.map({ $0 > 0 }) ?? true
        else { throw OperationsMetricsRebuildFailureV1.scaleLimitExceeded }

        let orderedSources = try Self.ordered(sources)
        let sourceSetSHA256 = try Self.sourceSetSHA256(orderedSources)
        let start = try Self.startIndex(
            continuation,
            sourceSetSHA256: sourceSetSHA256,
            sourceCount: orderedSources.count
        )
        let remaining = orderedSources.count - start
        let outputCount = min(remaining, maximumOutputs ?? remaining)
        let end = start + outputCount

        var values: [OperationsMetricsDerivedProjectionV1] = []
        values.reserveCapacity(end - start)
        for index in start..<end {
            try Task.checkCancellation()
            values.append(try Self.project(orderedSources[index]))
        }

        let next = end == orderedSources.count
            ? nil
            : try OperationsMetricsRebuildContinuationV1(
                sourceSetSHA256: sourceSetSHA256,
                nextSourceIndex: end
            )
        return .init(projections: values, continuation: next)
    }

    /// A corrupted nonpersistent value is never repaired in place.  Its
    /// validation failure makes it unusable until this pure rebuild succeeds.
    func validateOrDiscard(
        _ projection: OperationsMetricsDerivedProjectionV1?,
        expectedSourceClosureSHA256: String? = nil
    ) throws -> OperationsMetricsDerivedProjectionV1? {
        guard let projection else { return nil }
        do {
            if let expectedSourceClosureSHA256 {
                try ServiceReliabilityLimitsV1.digest(expectedSourceClosureSHA256)
            }
            try projection.validate()
            guard expectedSourceClosureSHA256 == nil
                    || projection.canonicalSourceClosureSHA256 == expectedSourceClosureSHA256
            else { throw OperationsMetricsRebuildFailureV1.corruptDerivedProjection }
            return projection
        } catch {
            throw OperationsMetricsRebuildFailureV1.corruptDerivedProjection
        }
    }

    func validateOrDiscard(
        _ projection: OperationsMetricsDerivedProjectionV1?,
        source: OperationsMetricsCanonicalSourceV1
    ) throws -> OperationsMetricsDerivedProjectionV1? {
        try validateOrDiscard(
            projection,
            expectedSourceClosureSHA256: try source.canonicalSourceClosureSHA256()
        )
    }

    private static func project(
        _ source: OperationsMetricsCanonicalSourceV1
    ) throws -> OperationsMetricsDerivedProjectionV1 {
        try source.validate()
        let canonicalSourceClosureSHA256 = try source.canonicalSourceClosureSHA256()
        let input = try ServiceReliabilityProjectionEngineV1.project(
            workspaceID: source.workspaceID,
            subject: source.subject,
            observationWindow: source.observationWindow,
            asOf: source.asOf,
            exposures: source.exposures,
            segments: source.segments,
            repairs: source.repairs,
            restorations: source.restorations
        )
        try input.validate()
        let dashboard = try DashboardProjectionV1(input: input)
        let timeline = try AssetServiceHistoryTimelineV1(
            workspaceID: source.workspaceID,
            subject: source.subject,
            incidents: source.incidents,
            impactSegments: source.segments,
            exposures: source.exposures,
            placementEvents: source.placementEvents,
            supplementalEvents: source.supplementalEvents
        )
        let report = try C53ServiceReliabilityReportProjectionRegistryV1.projection(input: input)
        let reportEnvelopes = try dashboard.metricProjections.map {
            try OperationsMetricsReportEnvelopeV1(projection: $0)
        }
        let openJSON = try WorkspaceMutationCanonicalV1.data(
            OperationsMetricsOpenJSONPayloadV1(
                dashboard: dashboard,
                timeline: timeline,
                reportEnvelopes: reportEnvelopes,
                canonicalSourceClosureSHA256: canonicalSourceClosureSHA256
            )
        )
        let value = OperationsMetricsDerivedProjectionV1(
            dashboard: dashboard,
            timeline: timeline,
            reportProjection: report,
            reportEnvelopes: reportEnvelopes,
            openJSON: openJSON,
            canonicalSourceClosureSHA256: canonicalSourceClosureSHA256
        )
        try value.validate()
        return value
    }

    private static func ordered(
        _ sources: [OperationsMetricsCanonicalSourceV1]
    ) throws -> [OperationsMetricsCanonicalSourceV1] {
        try sources.forEach { try $0.validate() }
        let ordered = sources.sorted { $0.stableIdentity < $1.stableIdentity }
        guard zip(ordered, ordered.dropFirst()).allSatisfy({
            $0.stableIdentity != $1.stableIdentity
        }) else { throw OperationsMetricsRebuildFailureV1.duplicateSource }
        return ordered
    }

    private static func sourceSetSHA256(
        _ sources: [OperationsMetricsCanonicalSourceV1]
    ) throws -> String {
        try ServiceReliabilityCanonicalCodecV1.sha256(
            sources.map { try $0.canonicalSourceClosureSHA256() }
        )
    }

    private static func startIndex(
        _ continuation: OperationsMetricsRebuildContinuationV1?,
        sourceSetSHA256: String,
        sourceCount: Int
    ) throws -> Int {
        guard let continuation else { return 0 }
        guard continuation.sourceSetSHA256 == sourceSetSHA256,
              continuation.nextSourceIndex <= sourceCount
        else { throw OperationsMetricsRebuildFailureV1.staleContinuation }
        return continuation.nextSourceIndex
    }
}

private struct OperationsMetricsCanonicalSourceClosureV1: Codable {
    let workspaceID: WorkspaceID
    let subject: ServiceReliabilitySubjectV1
    let observationWindow: ServiceReliabilityClosedIntervalV1
    let asOf: ServiceReliabilityInstantV1
    let incidents: [AssetServiceIncidentV1]
    let exposures: [QualifiedServiceExposureV1]
    let segments: [ServiceImpactSegmentV1]
    let repairs: [ServiceRepairIntervalV1]
    let restorations: [ServiceRestorationAssertionV1]
    let placementEvents: [AssetPoseEventV1]
    let supplementalEvents: [AssetServiceHistorySupplementalCanonicalEventV1]

    init(_ source: OperationsMetricsCanonicalSourceV1) {
        workspaceID = source.workspaceID
        subject = source.subject
        observationWindow = source.observationWindow
        asOf = source.asOf
        incidents = source.incidents.sorted {
            ($0.eventID.uuidString.lowercased(), $0.revision, $0.eventSHA256)
                < ($1.eventID.uuidString.lowercased(), $1.revision, $1.eventSHA256)
        }
        exposures = source.exposures.sorted {
            ($0.eventID.uuidString.lowercased(), $0.revision, $0.eventSHA256)
                < ($1.eventID.uuidString.lowercased(), $1.revision, $1.eventSHA256)
        }
        segments = source.segments.sorted {
            ($0.eventID.uuidString.lowercased(), $0.revision, $0.eventSHA256)
                < ($1.eventID.uuidString.lowercased(), $1.revision, $1.eventSHA256)
        }
        repairs = source.repairs.sorted {
            ($0.eventID.uuidString.lowercased(), $0.revision, $0.eventSHA256)
                < ($1.eventID.uuidString.lowercased(), $1.revision, $1.eventSHA256)
        }
        restorations = source.restorations.sorted {
            ($0.eventID.uuidString.lowercased(), $0.revision, $0.eventSHA256)
                < ($1.eventID.uuidString.lowercased(), $1.revision, $1.eventSHA256)
        }
        placementEvents = source.placementEvents.sorted {
            ($0.eventID.uuidString.lowercased(), $0.revision, $0.eventSHA256)
                < ($1.eventID.uuidString.lowercased(), $1.revision, $1.eventSHA256)
        }
        supplementalEvents = source.supplementalEvents.sorted {
            ($0.eventID.uuidString.lowercased(), $0.revision, $0.canonicalEventSHA256)
                < ($1.eventID.uuidString.lowercased(), $1.revision, $1.canonicalEventSHA256)
        }
    }
}

private struct OperationsMetricsOpenJSONPayloadV1: Codable, ServiceReliabilityCanonicalValidatingV1 {
    let schema: String
    let ordering: String
    let dashboard: DashboardProjectionV1
    let timeline: AssetServiceHistoryTimelineV1
    let reportEnvelopes: [OperationsMetricsReportEnvelopeV1]
    let canonicalSourceClosureSHA256: String

    init(
        dashboard: DashboardProjectionV1,
        timeline: AssetServiceHistoryTimelineV1,
        reportEnvelopes: [OperationsMetricsReportEnvelopeV1],
        canonicalSourceClosureSHA256: String
    ) {
        schema = OperationsMetricsOpenJSONV1.schema
        ordering = OperationsMetricsOpenJSONV1.deterministicOrdering
        self.dashboard = dashboard
        self.timeline = timeline
        self.reportEnvelopes = reportEnvelopes
        self.canonicalSourceClosureSHA256 = canonicalSourceClosureSHA256
    }

    func validate() throws {
        try dashboard.validate()
        try timeline.validate()
        try reportEnvelopes.forEach { try $0.validate() }
        try ServiceReliabilityLimitsV1.digest(canonicalSourceClosureSHA256)
        guard schema == OperationsMetricsOpenJSONV1.schema,
              ordering == OperationsMetricsOpenJSONV1.deterministicOrdering,
              dashboard.workspaceID == timeline.workspaceID,
              dashboard.subject == timeline.subject,
              reportEnvelopes.map(\.projection) == dashboard.metricProjections,
              reportEnvelopes.map(\.metricDefinitionID) == OperationsMetricDefinitionIDV1.allCases
        else { throw OperationsMetricsRebuildFailureV1.corruptDerivedProjection }
    }
}

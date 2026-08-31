import Foundation

enum ReliabilityMetricProjectionQualificationV1: String, Codable, Hashable, Sendable {
    case qualified = "QUALIFIED"
    case unavailable = "UNAVAILABLE"
}

struct ReliabilityMetricProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let definition: MetricDefinitionV1
    let workspaceID: WorkspaceID
    let subject: ServiceReliabilitySubjectV1
    let observationWindow: ServiceReliabilityClosedIntervalV1
    let asOf: ServiceReliabilityInstantV1
    let numeratorValue: UInt64
    let numeratorUnit: OperationsMetricUnitV1
    let denominatorValue: UInt64
    let denominatorUnit: OperationsMetricUnitV1
    let sampleCount: UInt64
    let qualification: ReliabilityMetricProjectionQualificationV1
    let unavailableReason: ServiceReliabilityUnavailableReasonV1?
    let includedSourceEventIDs: [UUID]
    let excludedSources: [ServiceReliabilityExcludedSourceV1]
    let qualifyingFailureStartEventIDs: [UUID]
    let inputProjectionSHA256: String
    let intervalUnionPolicySHA256: String
    let sourceClosureSHA256: String
    let availabilityNumeratorSHA256: String
    let projectionSHA256: String

    init(definition: MetricDefinitionV1, input: ReliabilityMetricInputProjectionV1) throws {
        try OperationsMetricsContractV1.validateRegistry()
        try definition.validate()
        try input.validate()
        let registered = try OperationsMetricsContractV1.definition(for: definition.identifier)
        guard registered == definition else { throw OperationsMetricsFailureV1.definitionOutputDisagreement }

        schemaVersion = Self.schemaVersion
        self.definition = definition
        workspaceID = input.workspaceID
        subject = input.subject
        observationWindow = input.observationWindow
        asOf = input.asOf
        numeratorValue = input.operatingExposureDurationMilliseconds
        numeratorUnit = definition.numeratorUnit
        includedSourceEventIDs = input.includedSourceEventIDs
        excludedSources = input.excludedSources
        qualifyingFailureStartEventIDs = input.qualifyingFailureStartEventIDs
        inputProjectionSHA256 = input.projectionSHA256
        intervalUnionPolicySHA256 = input.intervalUnionPolicySHA256
        sourceClosureSHA256 = input.sourceClosureSHA256
        availabilityNumeratorSHA256 = try ServiceReliabilityCanonicalCodecV1.sha256(input.operatingExposure)

        switch definition.identifier {
        case .qualifiedRecordedUnplannedMTBF:
            denominatorValue = UInt64(input.qualifyingFailureStartEventIDs.count)
            denominatorUnit = .componentCount
            sampleCount = denominatorValue
            (qualification, unavailableReason) = Self.status(input.mtbfQualification)
        case .qualifiedRecordedUnplannedFullInterruptionAvailability:
            denominatorValue = input.exposureDurationMilliseconds
            denominatorUnit = .qualifiedExposureMilliseconds
            sampleCount = 1
            (qualification, unavailableReason) = Self.status(input.availabilityQualification)
        }

        projectionSHA256 = try ServiceReliabilityCanonicalCodecV1.sha256(
            Basis(schemaVersion: Self.schemaVersion, definition: definition, workspaceID: input.workspaceID,
                  subject: input.subject, observationWindow: input.observationWindow, asOf: input.asOf,
                  numeratorValue: input.operatingExposureDurationMilliseconds, numeratorUnit: definition.numeratorUnit,
                  denominatorValue: denominatorValue, denominatorUnit: denominatorUnit, sampleCount: sampleCount,
                  qualification: qualification, unavailableReason: unavailableReason,
                  includedSourceEventIDs: includedSourceEventIDs, excludedSources: excludedSources,
                  qualifyingFailureStartEventIDs: qualifyingFailureStartEventIDs,
                  inputProjectionSHA256: input.projectionSHA256,
                  intervalUnionPolicySHA256: input.intervalUnionPolicySHA256,
                  sourceClosureSHA256: input.sourceClosureSHA256,
                  availabilityNumeratorSHA256: availabilityNumeratorSHA256)
        )
        try validate()
    }

    var value: ServiceReliabilityRationalV1? {
        get throws {
            guard qualification == .qualified else { return nil }
            return try .init(numerator: numeratorValue, denominator: denominatorValue)
        }
    }

    func validate() throws {
        try definition.validate()
        try subject.validate()
        try observationWindow.validate()
        try asOf.validate()
        try includedSourceEventIDs.forEach(ServiceReliabilityLimitsV1.id)
        try qualifyingFailureStartEventIDs.forEach(ServiceReliabilityLimitsV1.id)
        try excludedSources.forEach { try $0.validate() }
        try [inputProjectionSHA256, intervalUnionPolicySHA256, sourceClosureSHA256,
             availabilityNumeratorSHA256, projectionSHA256].forEach(ServiceReliabilityLimitsV1.digest)
        let registeredDefinition = try OperationsMetricsContractV1.definition(for: definition.identifier)
        guard schemaVersion == Self.schemaVersion,
              definition == registeredDefinition,
              workspaceID == subject.frozenScope.workspaceID,
              numeratorUnit == definition.numeratorUnit,
              denominatorUnit == definition.denominatorUnit,
              includedSourceEventIDs == includedSourceEventIDs.sorted(by: { $0.uuidString < $1.uuidString }),
              Set(includedSourceEventIDs).count == includedSourceEventIDs.count,
              qualifyingFailureStartEventIDs == qualifyingFailureStartEventIDs.sorted(by: { $0.uuidString < $1.uuidString }),
              Set(qualifyingFailureStartEventIDs).count == qualifyingFailureStartEventIDs.count,
              excludedSources == excludedSources.sorted(),
              Set(excludedSources).count == excludedSources.count,
              (qualification == .qualified) == (unavailableReason == nil),
              (qualification == .unavailable) == (unavailableReason != nil),
              (qualification == .unavailable || denominatorValue > 0),
              projectionSHA256 == (try ServiceReliabilityCanonicalCodecV1.sha256(basis))
        else { throw OperationsMetricsFailureV1.invalidProjection }

        switch definition.identifier {
        case .qualifiedRecordedUnplannedMTBF:
            guard denominatorValue == UInt64(qualifyingFailureStartEventIDs.count),
                  sampleCount == denominatorValue
            else { throw OperationsMetricsFailureV1.definitionOutputDisagreement }
        case .qualifiedRecordedUnplannedFullInterruptionAvailability:
            guard sampleCount == 1 else { throw OperationsMetricsFailureV1.definitionOutputDisagreement }
        }
    }

    private static func status(
        _ qualification: ServiceReliabilityQualificationV1
    ) -> (ReliabilityMetricProjectionQualificationV1, ServiceReliabilityUnavailableReasonV1?) {
        switch qualification {
        case .qualified: return (.qualified, nil)
        case .unavailable(let reason): return (.unavailable, reason)
        }
    }

    private var basis: Basis {
        .init(schemaVersion: schemaVersion, definition: definition, workspaceID: workspaceID, subject: subject,
              observationWindow: observationWindow, asOf: asOf, numeratorValue: numeratorValue,
              numeratorUnit: numeratorUnit, denominatorValue: denominatorValue, denominatorUnit: denominatorUnit,
              sampleCount: sampleCount, qualification: qualification, unavailableReason: unavailableReason,
              includedSourceEventIDs: includedSourceEventIDs, excludedSources: excludedSources,
              qualifyingFailureStartEventIDs: qualifyingFailureStartEventIDs, inputProjectionSHA256: inputProjectionSHA256,
              intervalUnionPolicySHA256: intervalUnionPolicySHA256, sourceClosureSHA256: sourceClosureSHA256,
              availabilityNumeratorSHA256: availabilityNumeratorSHA256)
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let definition: MetricDefinitionV1
        let workspaceID: WorkspaceID
        let subject: ServiceReliabilitySubjectV1
        let observationWindow: ServiceReliabilityClosedIntervalV1
        let asOf: ServiceReliabilityInstantV1
        let numeratorValue: UInt64
        let numeratorUnit: OperationsMetricUnitV1
        let denominatorValue: UInt64
        let denominatorUnit: OperationsMetricUnitV1
        let sampleCount: UInt64
        let qualification: ReliabilityMetricProjectionQualificationV1
        let unavailableReason: ServiceReliabilityUnavailableReasonV1?
        let includedSourceEventIDs: [UUID]
        let excludedSources: [ServiceReliabilityExcludedSourceV1]
        let qualifyingFailureStartEventIDs: [UUID]
        let inputProjectionSHA256: String
        let intervalUnionPolicySHA256: String
        let sourceClosureSHA256: String
        let availabilityNumeratorSHA256: String
    }
}

struct DashboardProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let subject: ServiceReliabilitySubjectV1
    let observationWindow: ServiceReliabilityClosedIntervalV1
    let asOf: ServiceReliabilityInstantV1
    let metricProjections: [ReliabilityMetricProjectionV1]
    let dashboardSHA256: String

    init(input: ReliabilityMetricInputProjectionV1) throws {
        try input.validate()
        schemaVersion = Self.schemaVersion
        workspaceID = input.workspaceID
        subject = input.subject
        observationWindow = input.observationWindow
        asOf = input.asOf
        metricProjections = try OperationsMetricsContractV1.metricDefinitions().map {
            try ReliabilityMetricProjectionV1(definition: $0, input: input)
        }
        dashboardSHA256 = try ServiceReliabilityCanonicalCodecV1.sha256(
            Basis(schemaVersion: Self.schemaVersion, workspaceID: input.workspaceID, subject: input.subject,
                  observationWindow: input.observationWindow, asOf: input.asOf, metricProjections: metricProjections)
        )
        try validate()
    }

    func validate() throws {
        try subject.validate()
        try observationWindow.validate()
        try asOf.validate()
        try metricProjections.forEach { try $0.validate() }
        try ServiceReliabilityLimitsV1.digest(dashboardSHA256)
        guard schemaVersion == Self.schemaVersion,
              workspaceID == subject.frozenScope.workspaceID,
              metricProjections.map(\.definition.identifier) == OperationsMetricDefinitionIDV1.allCases,
              metricProjections.allSatisfy { $0.workspaceID == workspaceID && $0.subject == subject &&
                  $0.observationWindow == observationWindow && $0.asOf == asOf },
              metricProjections[0].numeratorValue == metricProjections[1].numeratorValue,
              metricProjections[0].availabilityNumeratorSHA256 == metricProjections[1].availabilityNumeratorSHA256,
              dashboardSHA256 == (try ServiceReliabilityCanonicalCodecV1.sha256(basis))
        else { throw OperationsMetricsFailureV1.definitionOutputDisagreement }
    }

    private var basis: Basis {
        .init(schemaVersion: schemaVersion, workspaceID: workspaceID, subject: subject,
              observationWindow: observationWindow, asOf: asOf, metricProjections: metricProjections)
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let workspaceID: WorkspaceID
        let subject: ServiceReliabilitySubjectV1
        let observationWindow: ServiceReliabilityClosedIntervalV1
        let asOf: ServiceReliabilityInstantV1
        let metricProjections: [ReliabilityMetricProjectionV1]
    }
}

struct OperationsMetricsReportEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let metricDefinitionID: OperationsMetricDefinitionIDV1
    let metricDefinitionVersion: Int
    let metricDefinitionSHA256: String
    let projection: ReliabilityMetricProjectionV1
    let reportEnvelopeSHA256: String

    init(projection: ReliabilityMetricProjectionV1) throws {
        try projection.validate()
        schemaVersion = Self.schemaVersion
        metricDefinitionID = projection.definition.identifier
        metricDefinitionVersion = projection.definition.version
        metricDefinitionSHA256 = projection.definition.definitionSHA256
        self.projection = projection
        reportEnvelopeSHA256 = try ServiceReliabilityCanonicalCodecV1.sha256(
            Basis(schemaVersion: Self.schemaVersion, metricDefinitionID: projection.definition.identifier,
                  metricDefinitionVersion: projection.definition.version,
                  metricDefinitionSHA256: projection.definition.definitionSHA256, projection: projection)
        )
        try validate()
    }

    func validate() throws {
        try projection.validate()
        try ServiceReliabilityLimitsV1.digest(metricDefinitionSHA256)
        try ServiceReliabilityLimitsV1.digest(reportEnvelopeSHA256)
        let registeredDefinition = try OperationsMetricsContractV1.definition(for: metricDefinitionID)
        guard schemaVersion == Self.schemaVersion,
              registeredDefinition == projection.definition,
              metricDefinitionID == projection.definition.identifier,
              metricDefinitionVersion == projection.definition.version,
              metricDefinitionSHA256 == projection.definition.definitionSHA256,
              reportEnvelopeSHA256 == (try ServiceReliabilityCanonicalCodecV1.sha256(basis))
        else { throw OperationsMetricsFailureV1.definitionOutputDisagreement }
    }

    private var basis: Basis {
        .init(schemaVersion: schemaVersion, metricDefinitionID: metricDefinitionID,
              metricDefinitionVersion: metricDefinitionVersion, metricDefinitionSHA256: metricDefinitionSHA256,
              projection: projection)
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let metricDefinitionID: OperationsMetricDefinitionIDV1
        let metricDefinitionVersion: Int
        let metricDefinitionSHA256: String
        let projection: ReliabilityMetricProjectionV1
    }
}

enum OperationsMetricsOpenJSONV1 {
    static let schema = "OPERATIONS_METRICS_OPEN_JSON_V1"
    static let deterministicOrdering = "METRIC_DEFINITION_REGISTRY_ORDER"
    static let definitionAndDashboardAgreementRequired = true
}

enum AssetServiceHistoryEventKindV1: String, Codable, Hashable, Sendable {
    case incident = "ASSET_SERVICE_INCIDENT"
    case impactSegment = "SERVICE_IMPACT_SEGMENT"
    case qualifiedExposure = "QUALIFIED_SERVICE_EXPOSURE"
    case inspection = "INSPECTION"
    case finding = "FINDING"
    case correctiveWork = "CORRECTIVE_WORK"
    case recheck = "RECHECK"
    case report = "REPORT"
    case evidenceAssociation = "EVIDENCE_ASSOCIATION"
    case explicitAssetChange = "EXPLICIT_ASSET_CHANGE"
    case placementChange = "C37_PLACEMENT_CHANGE"
}

enum AssetServiceHistorySourceOwnerV1: String, Codable, Hashable, Sendable {
    case c53ServiceReliability = "C53_SERVICE_RELIABILITY"
    case c37PlacementPose = "C37_PLACEMENT_POSE"
    case inspection = "CANONICAL_INSPECTION"
    case finding = "CANONICAL_FINDING"
    case correctiveWork = "CANONICAL_CORRECTIVE_WORK"
    case recheck = "CANONICAL_RECHECK"
    case report = "CANONICAL_REPORT"
    case evidenceAssociation = "CANONICAL_EVIDENCE_ASSOCIATION"
    case explicitAssetChange = "CANONICAL_ASSET_CHANGE"
}

struct AssetServiceHistorySupplementalCanonicalEventV1: Codable, Equatable, Sendable {
    let kind: AssetServiceHistoryEventKindV1
    let sourceOwner: AssetServiceHistorySourceOwnerV1
    let workspaceID: WorkspaceID
    let assetID: UUID
    let eventID: UUID
    let revision: UInt64
    let occurredAt: ServiceReliabilityInstantV1
    let canonicalEventSHA256: String
    let supersedesEventID: UUID?
    let supersedesEventSHA256: String?

    func validate() throws {
        try ServiceReliabilityLimitsV1.id(assetID)
        try ServiceReliabilityLimitsV1.id(eventID)
        try occurredAt.validate()
        try ServiceReliabilityLimitsV1.digest(canonicalEventSHA256)
        if let supersedesEventID { try ServiceReliabilityLimitsV1.id(supersedesEventID) }
        if let supersedesEventSHA256 { try ServiceReliabilityLimitsV1.digest(supersedesEventSHA256) }
        guard revision > 0,
              (revision == 1) == (supersedesEventID == nil),
              (supersedesEventID == nil) == (supersedesEventSHA256 == nil),
              Self.expectedOwner(for: kind) == sourceOwner
        else { throw OperationsMetricsFailureV1.invalidProjection }
    }

    private static func expectedOwner(for kind: AssetServiceHistoryEventKindV1) -> AssetServiceHistorySourceOwnerV1? {
        switch kind {
        case .inspection: return .inspection
        case .finding: return .finding
        case .correctiveWork: return .correctiveWork
        case .recheck: return .recheck
        case .report: return .report
        case .evidenceAssociation: return .evidenceAssociation
        case .explicitAssetChange: return .explicitAssetChange
        default: return nil
        }
    }
}

struct AssetServiceHistoryEntryV1: Codable, Equatable, Sendable {
    let kind: AssetServiceHistoryEventKindV1
    let eventID: UUID
    let workspaceID: WorkspaceID
    let subject: ServiceReliabilitySubjectV1
    let sourceRevision: UInt64
    let recordedAt: ServiceReliabilityInstantV1
    let canonicalEventSHA256: String
    let sourceOwner: AssetServiceHistorySourceOwnerV1
    let supersedesEventID: UUID?
    let supersedesEventSHA256: String?

    func validate() throws {
        try ServiceReliabilityLimitsV1.id(eventID)
        try subject.validate()
        try recordedAt.validate()
        try ServiceReliabilityLimitsV1.digest(canonicalEventSHA256)
        if let supersedesEventID { try ServiceReliabilityLimitsV1.id(supersedesEventID) }
        if let supersedesEventSHA256 { try ServiceReliabilityLimitsV1.digest(supersedesEventSHA256) }
        guard sourceRevision > 0,
              workspaceID == subject.frozenScope.workspaceID,
              (sourceRevision == 1) == (supersedesEventID == nil),
              (supersedesEventID == nil) == (supersedesEventSHA256 == nil),
              Self.expectedOwner(for: kind) == sourceOwner
        else { throw OperationsMetricsFailureV1.invalidProjection }
    }

    private static func expectedOwner(for kind: AssetServiceHistoryEventKindV1) -> AssetServiceHistorySourceOwnerV1 {
        switch kind {
        case .incident, .impactSegment, .qualifiedExposure: return .c53ServiceReliability
        case .placementChange: return .c37PlacementPose
        case .inspection: return .inspection
        case .finding: return .finding
        case .correctiveWork: return .correctiveWork
        case .recheck: return .recheck
        case .report: return .report
        case .evidenceAssociation: return .evidenceAssociation
        case .explicitAssetChange: return .explicitAssetChange
        }
    }
}

struct AssetServiceHistoryTimelineV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let subject: ServiceReliabilitySubjectV1
    let entries: [AssetServiceHistoryEntryV1]
    let timelineSHA256: String

    init(
        workspaceID: WorkspaceID,
        subject: ServiceReliabilitySubjectV1,
        incidents: [AssetServiceIncidentV1],
        impactSegments: [ServiceImpactSegmentV1],
        exposures: [QualifiedServiceExposureV1],
        placementEvents: [AssetPoseEventV1] = [],
        supplementalEvents: [AssetServiceHistorySupplementalCanonicalEventV1] = []
    ) throws {
        try subject.validate()
        try incidents.forEach { try $0.validate() }
        try impactSegments.forEach { try $0.validate() }
        try exposures.forEach { try $0.validate() }
        try placementEvents.forEach { try $0.validateIntrinsic() }
        try supplementalEvents.forEach { try $0.validate() }
        guard subject.frozenScope.workspaceID == workspaceID,
              incidents.allSatisfy({ $0.workspaceID == workspaceID && $0.subject == subject }),
              impactSegments.allSatisfy({ $0.workspaceID == workspaceID && $0.subject == subject }),
              exposures.allSatisfy({ $0.workspaceID == workspaceID && $0.subject == subject }),
              placementEvents.allSatisfy({ $0.workspaceID == workspaceID && $0.assetID == subject.asset.subjectID }),
              supplementalEvents.allSatisfy({ $0.workspaceID == workspaceID && $0.assetID == subject.asset.subjectID })
        else { throw OperationsMetricsFailureV1.invalidProjection }

        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.subject = subject
        entries = try Self.entries(workspaceID: workspaceID, subject: subject, incidents: incidents, impactSegments: impactSegments, exposures: exposures,
                                  placementEvents: placementEvents, supplementalEvents: supplementalEvents)
        timelineSHA256 = try ServiceReliabilityCanonicalCodecV1.sha256(
            Basis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, subject: subject, entries: entries)
        )
        try validate()
    }

    func validate() throws {
        try subject.validate()
        try entries.forEach { try $0.validate() }
        try ServiceReliabilityLimitsV1.digest(timelineSHA256)
        guard schemaVersion == Self.schemaVersion,
              workspaceID == subject.frozenScope.workspaceID,
              entries == entries.sorted(by: Self.isOrdered),
              Set(entries.map(\.eventID)).count == entries.count,
              entries.allSatisfy({ $0.workspaceID == workspaceID && $0.subject == subject }),
              timelineSHA256 == (try ServiceReliabilityCanonicalCodecV1.sha256(basis))
        else { throw OperationsMetricsFailureV1.invalidProjection }
        try validatePredecessorClosure()
    }

    private func validatePredecessorClosure() throws {
        let byEventID = Dictionary(uniqueKeysWithValues: entries.map { ($0.eventID, $0) })
        var successorByPredecessorID: [UUID: UUID] = [:]
        for entry in entries {
            guard let predecessorID = entry.supersedesEventID else {
                guard entry.sourceRevision == 1 else { throw OperationsMetricsFailureV1.invalidProjection }
                continue
            }
            guard predecessorID != entry.eventID,
                  let predecessor = byEventID[predecessorID],
                  predecessor.canonicalEventSHA256 == entry.supersedesEventSHA256,
                  predecessor.workspaceID == entry.workspaceID,
                  predecessor.subject == entry.subject,
                  predecessor.kind == entry.kind,
                  predecessor.sourceOwner == entry.sourceOwner,
                  predecessor.recordedAt <= entry.recordedAt
            else { throw OperationsMetricsFailureV1.invalidProjection }
            let (expectedRevision, overflow) = predecessor.sourceRevision.addingReportingOverflow(1)
            guard !overflow, entry.sourceRevision == expectedRevision,
                  successorByPredecessorID[predecessorID] == nil
            else { throw OperationsMetricsFailureV1.invalidProjection }
            successorByPredecessorID[predecessorID] = entry.eventID
        }

        for entry in entries {
            var visited = Set<UUID>()
            var cursor: AssetServiceHistoryEntryV1? = entry
            while let current = cursor, let predecessorID = current.supersedesEventID {
                guard visited.insert(current.eventID).inserted,
                      let predecessor = byEventID[predecessorID]
                else { throw OperationsMetricsFailureV1.invalidProjection }
                cursor = predecessor
            }
        }
    }

    private static func entries(
        workspaceID: WorkspaceID,
        subject: ServiceReliabilitySubjectV1,
        incidents: [AssetServiceIncidentV1],
        impactSegments: [ServiceImpactSegmentV1],
        exposures: [QualifiedServiceExposureV1],
        placementEvents: [AssetPoseEventV1],
        supplementalEvents: [AssetServiceHistorySupplementalCanonicalEventV1]
    ) throws -> [AssetServiceHistoryEntryV1] {
        var output: [AssetServiceHistoryEntryV1] = []
        output += try incidents.map {
            try .init(kind: .incident, eventID: $0.eventID, workspaceID: workspaceID, subject: subject, sourceRevision: $0.revision,
                      recordedAt: .init($0.time.recordedAtUTC), canonicalEventSHA256: $0.eventSHA256,
                      sourceOwner: .c53ServiceReliability, supersedesEventID: $0.predecessor?.eventID,
                      supersedesEventSHA256: $0.predecessor?.eventSHA256)
        }
        output += try impactSegments.map {
            try .init(kind: .impactSegment, eventID: $0.eventID, workspaceID: workspaceID, subject: subject, sourceRevision: $0.revision,
                      recordedAt: .init($0.recordedTime.recordedAtUTC), canonicalEventSHA256: $0.eventSHA256,
                      sourceOwner: .c53ServiceReliability, supersedesEventID: $0.predecessor?.eventID,
                      supersedesEventSHA256: $0.predecessor?.eventSHA256)
        }
        output += try exposures.map {
            try .init(kind: .qualifiedExposure, eventID: $0.eventID, workspaceID: workspaceID, subject: subject, sourceRevision: $0.revision,
                      recordedAt: .init($0.timeBasis.recordedAtUTC), canonicalEventSHA256: $0.eventSHA256,
                      sourceOwner: .c53ServiceReliability, supersedesEventID: $0.predecessor?.eventID,
                      supersedesEventSHA256: $0.predecessor?.eventSHA256)
        }
        output += try placementEvents.map {
            try .init(kind: .placementChange, eventID: $0.eventID, workspaceID: workspaceID, subject: subject, sourceRevision: $0.revision,
                      recordedAt: .init($0.recordedAt), canonicalEventSHA256: $0.eventSHA256,
                      sourceOwner: .c37PlacementPose, supersedesEventID: $0.predecessor?.eventID,
                      supersedesEventSHA256: $0.predecessor?.eventSHA256)
        }
        output += supplementalEvents.map {
            .init(kind: $0.kind, eventID: $0.eventID, workspaceID: workspaceID, subject: subject, sourceRevision: $0.revision, recordedAt: $0.occurredAt,
                  canonicalEventSHA256: $0.canonicalEventSHA256, sourceOwner: $0.sourceOwner,
                  supersedesEventID: $0.supersedesEventID, supersedesEventSHA256: $0.supersedesEventSHA256)
        }
        guard Set(output.map(\.eventID)).count == output.count
        else { throw OperationsMetricsFailureV1.duplicateSourceEvent }
        return output.sorted(by: isOrdered)
    }

    private static func isOrdered(_ lhs: AssetServiceHistoryEntryV1, _ rhs: AssetServiceHistoryEntryV1) -> Bool {
        (lhs.recordedAt, lhs.kind.rawValue, lhs.eventID.uuidString) <
            (rhs.recordedAt, rhs.kind.rawValue, rhs.eventID.uuidString)
    }

    private var basis: Basis {
        .init(schemaVersion: schemaVersion, workspaceID: workspaceID, subject: subject, entries: entries)
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let workspaceID: WorkspaceID
        let subject: ServiceReliabilitySubjectV1
        let entries: [AssetServiceHistoryEntryV1]
    }
}

enum OperationsMetricsDerivedLifecycleV1 {
    static let storage = "NONPERSISTENT_DERIVED_ONLY"
    static let retry = "REBUILD_FROM_CANONICAL_C53_INPUTS_WITH_UNIQUE_EVENT_REVISION"
    static let deletion = "DROP_DERIVED_AND_REBUILD"
    static let restore = "DROP_DERIVED_AND_REBUILD"
    static let replay = "REBUILD_FROM_CANONICAL_C53_INPUTS"
    static let corruptState = "DISCARD_AND_FAIL_CLOSED_UNTIL_REBUILT"
}

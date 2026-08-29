import Foundation

/// Immutable, renderer-neutral projection of a completed guided survey.  It
/// deliberately carries completion facts and the subject as published, but no
/// pass/fail, compliance, or later subject-promotion inference.
struct SurveyPublicationReportProjectionV1: Codable, Equatable, Sendable {
    static let projectionVersion = "SURVEY_PUBLICATION_REPORT_V1"

    let projectionVersion: String
    let snapshotID: UUID
    let workspaceID: WorkspaceID
    let sessionID: UUID
    let sessionRevision: UInt64
    let publicationRevision: UInt64
    let publicationSHA256: String
    let definitionReleaseID: UUID
    let definitionRevision: UInt64
    let definitionSHA256: String
    let packageReleaseID: String
    let packageID: String
    let packageContentVersion: Int
    let packageSHA256: String
    let workflowSHA256: String
    let subjectAtPublication: SurveySessionSubjectV1
    let factCount: Int
    let evidenceCount: Int

    init(publication: SurveyPublicationSnapshotV1) throws {
        try publication.validateIntrinsic()
        projectionVersion = Self.projectionVersion
        snapshotID = publication.snapshotID
        workspaceID = publication.workspaceID
        sessionID = publication.sessionID
        sessionRevision = publication.sessionRevision
        publicationRevision = publication.revision
        publicationSHA256 = publication.snapshotSHA256
        definitionReleaseID = publication.authority.definitionRelease.releaseID
        definitionRevision = publication.authority.definitionRelease.revision
        definitionSHA256 = publication.authority.definitionRelease.releaseSHA256
        packageReleaseID = publication.authority.packageRelease.packageReleaseID
        packageID = publication.authority.packageRelease.packageID
        packageContentVersion = publication.authority.packageRelease.packageContentVersion
        packageSHA256 = publication.authority.packageRelease.packageSHA256
        workflowSHA256 = publication.authority.packageRelease.workflowSHA256
        subjectAtPublication = publication.subjectAtPublication
        factCount = publication.facts.count
        evidenceCount = publication.facts.reduce(0) { $0 + $1.evidence.count }
        try validate()
    }

    func validate() throws {
        try subjectAtPublication.validate()
        let subjectRevisionFits: Bool
        switch subjectAtPublication {
        case .canonical(let reference): subjectRevisionFits = reference.revision <= UInt64(Int.max)
        case .provisional(let reference): subjectRevisionFits = reference.revision <= UInt64(Int.max)
        }
        guard projectionVersion == Self.projectionVersion,
              snapshotID != UUID.zero,
              sessionID != UUID.zero,
              sessionRevision > 0,
              publicationRevision > 0,
              definitionReleaseID != UUID.zero,
              definitionRevision > 0,
              subjectRevisionFits,
              packageContentVersion > 0,
              WorkflowGrammarValidationV1.validID(packageID),
              MutationEnvelopeV1.isSHA256(packageReleaseID),
              MutationEnvelopeV1.isSHA256(packageSHA256),
              MutationEnvelopeV1.isSHA256(workflowSHA256),
              MutationEnvelopeV1.isSHA256(publicationSHA256),
              MutationEnvelopeV1.isSHA256(definitionSHA256),
              factCount >= 0,
              evidenceCount >= 0 else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

// MARK: - C28 frozen schedule and occurrence report projection

/// C28 keeps schedule truth in the workflow contracts.  This is a bounded
/// report projection over those records: it carries the frozen time basis,
/// occurrence history facts, and the hashes of disposable due/reminder
/// projections without copying actor, work-instance, or notification data.
enum ScheduleReportProjectionFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidState
    case invalidDigest
    case wrongWorkspace
    case duplicateOccurrence
    case missingHistory
    case unsupportedFormat
}

struct ScheduleOccurrenceReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let occurrenceID: OccurrenceIDV1
    let state: OccurrenceStateV1
    let scheduleRelease: ScheduleDefinitionReleaseReferenceV1
    let nominalBasis: ResolvedOccurrenceBasisV1
    let effectiveBasis: ResolvedOccurrenceBasisV1
    let historyEventSHA256: String
    let workInstanceRecorded: Bool

    init(
        event: OccurrenceHistoryEventV1,
        entry: DueQueueEntryV1
    ) throws {
        try event.validateIntrinsic()
        guard event.occurrenceID == entry.occurrenceID,
              event.scheduleRelease == entry.scheduleRelease,
              event.effectiveBasis.resolvedAtUTC == entry.effectiveDueAtUTC,
              OccurrenceStateV1.allCases.contains(entry.state),
              KernelCanonicalHashV1.validSHA256(event.eventSHA256) else {
            throw ScheduleReportProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        occurrenceID = event.occurrenceID
        state = entry.state
        scheduleRelease = event.scheduleRelease
        nominalBasis = event.nominalBasis
        effectiveBasis = event.effectiveBasis
        historyEventSHA256 = event.eventSHA256
        workInstanceRecorded = event.workInstance != nil
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              OccurrenceStateV1.allCases.contains(state),
              KernelCanonicalHashV1.validSHA256(historyEventSHA256) else {
            throw ScheduleReportProjectionFailureV1.invalidState
        }
        try occurrenceID.validate()
        try scheduleRelease.validate()
        try nominalBasis.validate()
        try effectiveBasis.validate()
    }
}

struct ScheduleReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let projectionVersion = "SCHEDULE_REPORT_PROJECTION_V1"

    let schemaVersion: Int
    let projectionVersion: String
    let workspaceID: UUID
    let scheduleDefinitionID: UUID
    let scheduleRelease: ScheduleDefinitionReleaseReferenceV1
    let lifecycleState: ScheduleLifecycleStateV1
    /// This is a presentation discriminator derived from the canonical
    /// `ScheduleRecurrenceV1`; it is never used to resolve occurrences.
    let recurrenceKind: String
    let timeBasis: FrozenScheduleTimeBasisV1
    let evaluatedAt: Date
    let occurrences: [ScheduleOccurrenceReportProjectionV1]
    let dueQueueProjectionSHA256: String
    let reminderProjectionSHA256: String?
    let sourceClosureSHA256: String
    let historyFrozen: Bool
    let notificationDeliveryIsTruth: Bool
    let projectionSHA256: String

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let projectionVersion: String
        let workspaceID: UUID
        let scheduleDefinitionID: UUID
        let scheduleRelease: ScheduleDefinitionReleaseReferenceV1
        let lifecycleState: ScheduleLifecycleStateV1
        let recurrenceKind: String
        let timeBasis: FrozenScheduleTimeBasisV1
        let evaluatedAt: Date
        let occurrences: [ScheduleOccurrenceReportProjectionV1]
        let dueQueueProjectionSHA256: String
        let reminderProjectionSHA256: String?
        let sourceClosureSHA256: String
        let historyFrozen: Bool
        let notificationDeliveryIsTruth: Bool
    }

    init(
        definition: ScheduleDefinitionReleaseV1,
        dueQueue: DueQueueProjectionV1,
        history: [OccurrenceHistoryEventV1],
        reminder: ReminderProjectionV1? = nil,
        evaluatedAt: Date? = nil
    ) throws {
        try definition.validate()
        guard dueQueue.workspaceID == definition.workspaceID,
              dueQueue.entries.count <= definition.maximumGeneratedOccurrences,
              KernelCanonicalHashV1.validSHA256(dueQueue.sourceClosureSHA256),
              KernelCanonicalHashV1.validSHA256(dueQueue.projectionSHA256),
              history.count <= definition.maximumGeneratedOccurrences else {
            throw ScheduleReportProjectionFailureV1.wrongWorkspace
        }

        let release = try ScheduleDefinitionReleaseReferenceV1(definition)
        guard dueQueue.entries.allSatisfy({ $0.scheduleRelease == release }),
              history.allSatisfy({ $0.workspaceID == definition.workspaceID }) else {
            throw ScheduleReportProjectionFailureV1.wrongWorkspace
        }

        var latestByOccurrence: [OccurrenceIDV1: OccurrenceHistoryEventV1] = [:]
        for group in Dictionary(grouping: history, by: \.occurrenceID).values {
            let ordered = group.sorted { $0.revision < $1.revision }
            guard let first = ordered.first, first.revision == 1 else {
                throw ScheduleReportProjectionFailureV1.invalidValue
            }
            try first.validate(predecessor: nil)
            if ordered.count > 1 {
                for index in 1..<ordered.count {
                    try ordered[index].validate(predecessor: ordered[index - 1])
                }
            }
            guard let latest = ordered.last else {
                throw ScheduleReportProjectionFailureV1.missingHistory
            }
            latestByOccurrence[latest.occurrenceID] = latest
        }

        let values = try dueQueue.entries.sorted {
            if $0.occurrenceID != $1.occurrenceID {
                return $0.occurrenceID < $1.occurrenceID
            }
            return $0.scheduleRelease.releaseID.uuidString < $1.scheduleRelease.releaseID.uuidString
        }.map { entry -> ScheduleOccurrenceReportProjectionV1 in
            guard let event = latestByOccurrence[entry.occurrenceID],
                  event.scheduleRelease == entry.scheduleRelease else {
                throw ScheduleReportProjectionFailureV1.missingHistory
            }
            return try ScheduleOccurrenceReportProjectionV1(event: event, entry: entry)
        }
        guard Set(values.map(\.occurrenceID)).count == values.count else {
            throw ScheduleReportProjectionFailureV1.duplicateOccurrence
        }

        if let reminder {
            guard reminder.workspaceID == definition.workspaceID,
                  reminder.dueQueueSHA256 == dueQueue.projectionSHA256,
                  KernelCanonicalHashV1.validSHA256(reminder.projectionSHA256) else {
                throw ScheduleReportProjectionFailureV1.invalidDigest
            }
        }

        schemaVersion = Self.schemaVersion
        projectionVersion = Self.projectionVersion
        workspaceID = definition.workspaceID.rawValue
        scheduleDefinitionID = definition.scheduleDefinitionID
        scheduleRelease = release
        lifecycleState = definition.lifecycleState
        switch definition.recurrence {
        case .fixedCalendar: recurrenceKind = "FIXED_CALENDAR"
        case .completionRelative: recurrenceKind = "COMPLETION_RELATIVE"
        }
        timeBasis = definition.timeBasis
        self.evaluatedAt = evaluatedAt ?? dueQueue.evaluatedAt
        occurrences = values
        dueQueueProjectionSHA256 = dueQueue.projectionSHA256
        reminderProjectionSHA256 = reminder?.projectionSHA256
        sourceClosureSHA256 = dueQueue.sourceClosureSHA256
        historyFrozen = true
        notificationDeliveryIsTruth = false
        projectionSHA256 = try ScheduleCanonicalCodecV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                projectionVersion: Self.projectionVersion,
                workspaceID: workspaceID,
                scheduleDefinitionID: scheduleDefinitionID,
                scheduleRelease: scheduleRelease,
                lifecycleState: lifecycleState,
                recurrenceKind: recurrenceKind,
                timeBasis: timeBasis,
                evaluatedAt: self.evaluatedAt,
                occurrences: occurrences,
                dueQueueProjectionSHA256: dueQueueProjectionSHA256,
                reminderProjectionSHA256: reminderProjectionSHA256,
                sourceClosureSHA256: sourceClosureSHA256,
                historyFrozen: historyFrozen,
                notificationDeliveryIsTruth: notificationDeliveryIsTruth
            )
        )
        try validate()
    }

    func validate() throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard schemaVersion == Self.schemaVersion,
              projectionVersion == Self.projectionVersion,
              workspaceID != zero,
              scheduleDefinitionID != zero,
              recurrenceKind == "FIXED_CALENDAR" || recurrenceKind == "COMPLETION_RELATIVE",
              historyFrozen,
              !notificationDeliveryIsTruth,
              evaluatedAt.timeIntervalSinceReferenceDate.isFinite,
              occurrences.count <= ScheduleLimitsV1.maximumGeneratedOccurrences,
              occurrences == occurrences.sorted(by: { $0.occurrenceID < $1.occurrenceID }),
              Set(occurrences.map(\.occurrenceID)).count == occurrences.count,
              KernelCanonicalHashV1.validSHA256(dueQueueProjectionSHA256),
              KernelCanonicalHashV1.validSHA256(sourceClosureSHA256),
              reminderProjectionSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true else {
            throw ScheduleReportProjectionFailureV1.invalidValue
        }
        try scheduleRelease.validate()
        try timeBasis.validate()
        try occurrences.forEach { try $0.validate() }
        guard scheduleRelease.scheduleDefinitionID == scheduleDefinitionID,
              projectionSHA256 == (try ScheduleCanonicalCodecV1.sha256(
                  DigestBasis(
                      schemaVersion: schemaVersion,
                      projectionVersion: projectionVersion,
                      workspaceID: workspaceID,
                      scheduleDefinitionID: scheduleDefinitionID,
                      scheduleRelease: scheduleRelease,
                      lifecycleState: lifecycleState,
                      recurrenceKind: recurrenceKind,
                      timeBasis: timeBasis,
                      evaluatedAt: evaluatedAt,
                      occurrences: occurrences,
                      dueQueueProjectionSHA256: dueQueueProjectionSHA256,
                      reminderProjectionSHA256: reminderProjectionSHA256,
                      sourceClosureSHA256: sourceClosureSHA256,
                      historyFrozen: historyFrozen,
                      notificationDeliveryIsTruth: notificationDeliveryIsTruth
                  )
              )) else {
            throw ScheduleReportProjectionFailureV1.invalidDigest
        }
    }
}

enum ScheduleReportProjectionPolicyV1 {
    static let sectionID = "schedule"
    static let sectionVersion = 1
    static let projectionVersion = ScheduleReportProjectionV1.projectionVersion
    static let sourceOfTruth = "CANONICAL_SCHEDULE_RELEASE_AND_OCCURRENCE_HISTORY"
    static let supportedFormats: [ReportProjectionFormatV1] = [.openJSON, .pdf, .structuredText]
    static let metadataOnly = true
    static let derivedOnly = true
    static let historicalDisplayIsFrozen = true
    static let notificationDeliveryIsTruth = false
    static let excludesNotificationPayload = true
    static let excludesActorIdentity = true
    static let excludesWorkInstanceIdentity = true

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }

    static func validate(
        _ projection: ScheduleReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> ScheduleReportProjectionV1 {
        guard supports(format), metadataOnly, derivedOnly,
              historicalDisplayIsFrozen, !notificationDeliveryIsTruth,
              excludesNotificationPayload, excludesActorIdentity,
              excludesWorkInstanceIdentity else {
            throw ScheduleReportProjectionFailureV1.unsupportedFormat
        }
        try projection.validate()
        return projection
    }
}

enum SurveyPublicationReportBoundaryV1 {
    static let semanticTreeIsDerivedOnly = true
    static let laterPromotionRewritesFrozenSubject = false
    static let surveyPassFailMeaningIsDeclared = false
}

enum ReportAudienceV1: String, Codable, CaseIterable, Hashable, Sendable {
    case internalUse = "INTERNAL"
    case customerSafe = "CUSTOMER_SAFE"
}

enum ReportProjectionAccessibleDocumentBoundaryV1{
    static let semanticTreeDerivedFromAudienceProjection=true
    static let semanticTreeMutatesSnapshot=false
    static let customerSafeMayContainInternalNodes=false
}

/// C19 report projection for one immutable, locally recorded measurement.
/// Values remain fixed-point and units remain typed identifiers; private
/// operator, serial, manufacturer, model, response, and evidence content are
/// deliberately absent from this audience-safe projection.
struct MeasurementIntegrityReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let captureID: UUID
    let workspaceID: WorkspaceID
    let packageReleaseID: String
    let workflowSHA256: String
    let enteredValue: ExactDecimalV1
    let enteredUnitID: String
    let canonicalValue: ExactDecimalV1
    let canonicalUnitID: String
    let dimension: MeasurementDimensionV1
    let precisionScale: Int
    let uncertaintyCanonical: ExactDecimalV1?
    let source: MeasurementSourceV1
    let sourceMode: MeasurementCaptureSourceModeV1
    let captureMethodID: String
    let instrumentReferenceID: UUID?
    let instrumentID: UUID?
    let instrumentKind: InstrumentKindV1?
    let instrumentLifecycleState: InstrumentLifecycleStateV1?
    let calibrationSnapshotID: UUID?
    let calibrationStatus: CalibrationStatusV1?
    let calibrationBasis: CalibrationBasisV1?
    let seriesID: UUID?
    let seriesState: MeasurementSeriesStateV1?
    let seriesExpectedSampleCount: Int?
    let seriesObservedSampleCount: Int?
    let protocolReleaseID: UUID?
    let protocolRevision: UInt64?
    let aggregationPolicy: MeasurementAggregationPolicyV1?
    let qualityResult: MeasurementQualityResultV1?
    let qualityReasonCodes: [MeasurementQualityReasonV1]
    let qualityPolicyVersion: String?
    let qualityPolicySHA256: String?
    let capturedAt: Date
    let revision: UInt64
    let captureSHA256: String

    init(
        capture: MeasurementCaptureV1,
        instrument: InstrumentReferenceV1? = nil,
        calibration: CalibrationStatusSnapshotV1? = nil,
        series: MeasurementSeriesV1? = nil,
        quality: MeasurementQualityAssessmentV1? = nil
    ) throws {
        try capture.validateClosure(instrument: instrument, calibration: calibration)
        try instrument?.validate()
        try calibration?.validate()
        try series?.validate()
        try quality?.validate()
        if let instrument {
            guard capture.workspaceID == instrument.workspaceID,
                  capture.sourceMode == .localObservation else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        } else {
            guard capture.sourceMode == .manualEntry, calibration == nil else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
        if let instrument {
            let reference = try InstrumentRevisionReferenceV1(instrument)
            guard capture.instrument == reference else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
        if let calibration {
            let reference = try CalibrationSnapshotReferenceV1(calibration)
            guard capture.calibration == reference else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
        if let series {
            guard series.workspaceID == capture.workspaceID,
                  series.samples.contains(where: { $0.captureID == capture.captureID
                      && $0.revision == capture.revision
                      && $0.captureSHA256 == capture.captureSHA256 }) else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
        if let quality {
            guard quality.workspaceID == capture.workspaceID,
                  (quality.subjectKind == .capture && quality.subjectID == capture.captureID
                      && quality.subjectRevision == capture.revision
                      && quality.subjectSHA256 == capture.captureSHA256)
                      || (quality.subjectKind == .series && series != nil
                          && quality.subjectID == series?.seriesID
                          && quality.subjectRevision == series?.revision
                          && quality.subjectSHA256 == series?.seriesSHA256) else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }

        schemaVersion = Self.schemaVersion
        captureID = capture.captureID
        workspaceID = capture.workspaceID
        packageReleaseID = capture.packageReleaseID
        workflowSHA256 = capture.workflowSHA256
        enteredValue = capture.measurement.enteredValue
        enteredUnitID = capture.measurement.enteredUnitID
        canonicalValue = capture.measurement.canonicalValue
        canonicalUnitID = capture.measurement.canonicalUnitID
        dimension = capture.measurement.dimension
        precisionScale = capture.measurement.precisionScale
        uncertaintyCanonical = capture.measurement.uncertaintyCanonical
        source = capture.measurement.source
        sourceMode = capture.sourceMode
        captureMethodID = capture.measurement.captureMethodID
        instrumentReferenceID = capture.instrument?.referenceID
        instrumentID = instrument?.instrumentID ?? capture.instrument?.instrumentID
        instrumentKind = instrument?.kind
        instrumentLifecycleState = instrument?.lifecycleState
        calibrationSnapshotID = calibration?.snapshotID ?? capture.calibration?.snapshotID
        calibrationStatus = calibration?.status
        calibrationBasis = calibration?.basis
        seriesID = series?.seriesID
        seriesState = series?.state
        seriesExpectedSampleCount = series?.expectedSampleCount
        seriesObservedSampleCount = series?.observedSampleCount
        protocolReleaseID = series?.protocolReference.releaseID
        protocolRevision = series?.protocolReference.revision
        aggregationPolicy = series?.aggregationPolicy
        qualityResult = quality?.result
        qualityReasonCodes = quality?.reasonCodes ?? []
        qualityPolicyVersion = quality?.policyVersion
        qualityPolicySHA256 = quality?.policySHA256
        capturedAt = capture.capturedAt
        revision = capture.revision
        captureSHA256 = capture.captureSHA256
        try validate()
    }

    func validate() throws {
        guard let expectedDigest = try? Self.digest(
            workspaceID: workspaceID,
            manifestID: manifestID,
            reviewReceiptID: reviewReceiptID,
            policyID: policyID,
            audience: audience,
            derivativeContentID: derivativeContentID,
            derivativeSHA256: derivativeSHA256,
            sourceRevision: sourceRevision,
            sourceSHA256: sourceSHA256,
            policyRevision: policyRevision,
            policySHA256: policySHA256,
            reviewRevision: reviewRevision,
            reviewSHA256: reviewSHA256,
            reviewDecision: reviewDecision,
            staleState: staleState,
            metadataSanitized: metadataSanitized,
            redactionDeclared: redactionDeclared,
            derivativeOnly: derivativeOnly,
            originalReferenceExcluded: originalReferenceExcluded,
            transformKinds: transformKinds,
            regionCount: regionCount
        ) else {
            throw PrivacyTransformReportProjectionFailureV1.invalidValue
        }
        guard schemaVersion == Self.schemaVersion,
              captureID != SearchContractValidationV1.zeroUUID,
              KernelCanonicalHashV1.validSHA256(packageReleaseID),
              KernelCanonicalHashV1.validSHA256(workflowSHA256),
              KernelCanonicalHashV1.validSHA256(captureSHA256),
              SnapshotProjectionValidationV1.validID(enteredUnitID),
              SnapshotProjectionValidationV1.validID(canonicalUnitID),
              precisionScale == canonicalValue.scale,
              MeasurementIntegrityValidationV1.token(captureMethodID),
              revision > 0,
              qualityReasonCodes == qualityReasonCodes.sorted(),
              Set(qualityReasonCodes).count == qualityReasonCodes.count else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        guard (try? ExactDecimalV1(mantissa: enteredValue.mantissa, scale: enteredValue.scale)) != nil,
              (try? ExactDecimalV1(mantissa: canonicalValue.mantissa, scale: canonicalValue.scale)) != nil,
              (uncertaintyCanonical == nil
                  || (try? ExactDecimalV1(
                      mantissa: uncertaintyCanonical!.mantissa,
                      scale: uncertaintyCanonical!.scale
                  )) != nil) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        guard source == (sourceMode == .manualEntry ? .manualEntry : .instrumentObserved) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        switch sourceMode {
        case .manualEntry:
            guard instrumentReferenceID == nil, instrumentID == nil,
                  instrumentKind == nil, instrumentLifecycleState == nil,
                  calibrationSnapshotID == nil, calibrationStatus == nil,
                  calibrationBasis == nil else {
                throw SnapshotProjectionFailureV1.invalidValue
            }
        case .localObservation:
            guard instrumentReferenceID != nil, instrumentID != nil,
                  instrumentKind != nil, instrumentLifecycleState != nil,
                  calibrationSnapshotID != nil, calibrationStatus != nil,
                  calibrationBasis != nil else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
        }
        if let seriesID {
            guard seriesID != SearchContractValidationV1.zeroUUID,
                  let seriesState,
                  let expected = seriesExpectedSampleCount,
                  let observed = seriesObservedSampleCount,
                  expected > 0, observed >= 0, observed <= expected,
                  protocolReleaseID != nil, (protocolRevision ?? 0) > 0,
                  aggregationPolicy != nil else {
                throw SnapshotProjectionFailureV1.invalidValue
            }
            _ = seriesState
        } else {
            guard seriesState == nil, seriesExpectedSampleCount == nil,
                  seriesObservedSampleCount == nil, protocolReleaseID == nil,
                  protocolRevision == nil, aggregationPolicy == nil else {
                throw SnapshotProjectionFailureV1.invalidValue
            }
        }
        if qualityResult == nil {
            guard qualityReasonCodes.isEmpty, qualityPolicyVersion == nil,
                  qualityPolicySHA256 == nil else {
                throw SnapshotProjectionFailureV1.invalidValue
            }
        } else {
            guard !qualityReasonCodes.isEmpty,
                  let policyVersion = qualityPolicyVersion,
                  MeasurementIntegrityValidationV1.token(policyVersion),
                  let policySHA256 = qualityPolicySHA256,
                  KernelCanonicalHashV1.validSHA256(policySHA256) else {
                throw SnapshotProjectionFailureV1.invalidValue
            }
            let positiveReasons: Set<MeasurementQualityReasonV1> = [
                .declaredChecksClear, .calibrationNotRequired,
            ]
            let reasons = Set(qualityReasonCodes)
            guard let qualityResult else {
                throw SnapshotProjectionFailureV1.invalidValue
            }
            switch qualityResult {
            case .clear:
                guard reasons.isSubset(of: positiveReasons) else {
                    throw SnapshotProjectionFailureV1.invalidValue
                }
            case .reviewRequired:
                guard !reasons.isSubset(of: positiveReasons),
                      !reasons.contains(.humanOverride) else {
                    throw SnapshotProjectionFailureV1.invalidValue
                }
            case .overridden:
                guard reasons.contains(.humanOverride) else {
                    throw SnapshotProjectionFailureV1.invalidValue
                }
            }
        }
        guard revision <= UInt64(Int.max),
              protocolRevision.map({ $0 <= UInt64(Int.max) }) ?? true,
              capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

enum ReportMeasurementIntegrityProjectionPolicyV1 {
    static let sectionID = "measurement-integrity"
    static let sectionVersion = 1
    static let projectionVersion = "report-measurement-integrity-v1"
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let supportedFormats: [ReportProjectionFormatV1] = [.openJSON, .pdf, .structuredText]
    static let requiresExactFixedPointValues = true
    static let freezesUnitMeaning = true
    static let excludesOpaqueSerial = true
    static let excludesOperatorIdentity = true
    static let excludesEvidenceLocators = true
    static let excludesRawResponse = true
    static let excludesUnsupportedClaims = true

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }
}

typealias C19MeasurementIntegrityReportProjectionV1 = MeasurementIntegrityReportProjectionV1

enum ReportDetailLevelV1: String, Codable, CaseIterable, Hashable, Sendable {
    case summary = "SUMMARY"
    case complete = "COMPLETE"
}

enum ReportProjectionFormatV1: String, Codable, CaseIterable, Hashable, Sendable {
    case pdf = "PDF"
    case openJSON = "OPEN_JSON"
    case structuredText = "STRUCTURED_TEXT"
    case formulaSafeCSV = "FORMULA_SAFE_CSV"
    case media = "MEDIA"
    case manifest = "MANIFEST"
}

enum ReportMediaLayoutV1: String, Codable, CaseIterable, Hashable, Sendable {
    case none = "NONE"
    case compactGrid = "COMPACT_GRID"
    case standardGrid = "STANDARD_GRID"
    case fullWidth = "FULL_WIDTH"
}

enum ReportOrientationV1: String, Codable, CaseIterable, Hashable, Sendable {
    case portrait = "PORTRAIT"
    case landscape = "LANDSCAPE"
}

enum ReportPackagingV1: String, Codable, CaseIterable, Hashable, Sendable {
    case combined = "COMBINED"
    case separatePerWorkItem = "SEPARATE_PER_WORK_ITEM"
}

enum ReportPrivacyClassV1: String, Codable, CaseIterable, Hashable, Sendable {
    case mandatoryPublicTruth = "MANDATORY_PUBLIC_TRUTH"
    case audienceSafe = "AUDIENCE_SAFE"
    case internalOnly = "INTERNAL_ONLY"
}

/// Additive report policy for the C38 accountability projection.  The
/// section is audience-safe because it carries local assertions and recorded
/// provenance only; contact points, identity verification, and legal-signature
/// claims remain outside this projection.
enum ReportAccountabilityProjectionPolicyV1 {
    static let sectionID = "accountability"
    static let sectionVersion = 1
    static let projectionVersion = "report-accountability-v1"
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let excludesContactPoints = true
    static let excludesIdentityAndLegalClaims = true
    static let supportedFormats: [ReportProjectionFormatV1] = [
        .openJSON, .structuredText,
    ]

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }
}

/// Additive C39 report policy.  Semantic and lifecycle records are frozen
/// projections; operational disposition, safety/recall claims, and raw
/// product-identifier values are never inferred or emitted by this section.
enum ReportAssetSemanticsProjectionPolicyV1 {
    static let sectionID = "asset-semantics"
    static let sectionVersion = 1
    static let projectionVersion = "report-asset-semantics-v1"
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let excludesOperationalDisposition = true
    static let excludesProductIdentifierValues = true
    static let excludesSafetyAndRecallClaims = true
    static let supportedFormats: [ReportProjectionFormatV1] = [
        .openJSON, .structuredText,
    ]

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }
}

/// C40 authority and criterion facts are reported as an exact historic basis,
/// never as an app-origin legal, safety, compliance, AHJ, or professional claim.
enum ReportAuthorityCriterionProjectionPolicyV1 {
    static let sectionID = "authority-criterion"
    static let sectionVersion = 1
    static let projectionVersion = "report-authority-criterion-v1"
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let requiredWording = "assessed against"
    static let localizationKeys: [AuthorityCriterionLocalizationKeyV1] = [
        .authoritySource,
        .applicability,
        .criterionResult,
        .severity,
        .measurementProtocol,
        .technicalBasis,
        .assessedAgainst,
        .nextStep,
    ]
    static let excludesLicensedSourceBytes = true
    static let excludesRawLocators = true
    static let excludesLegalSafetyComplianceClaims = true
    static let supportedFormats: [ReportProjectionFormatV1] = [
        .openJSON, .structuredText,
    ]

    static func applicabilityLocalizationKey(
        _ disposition: ApplicabilityDispositionV1
    ) -> AuthorityCriterionLocalizationKeyV1 {
        AuthorityCriterionLocalizationKeyV1.applicabilityKey(disposition)
    }

    static func resultLocalizationKey(
        _ result: ScreeningCriterionResultV1
    ) -> AuthorityCriterionLocalizationKeyV1 {
        AuthorityCriterionLocalizationKeyV1.resultKey(result)
    }

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }
}

/// C41 frozen functional-relationship report section.  This is a typed,
/// audience-safe history projection: it carries descriptor identity, direction,
/// state, bounds, and site policy without turning an association into a
/// placement, ownership, authorization, compliance, or telemetry claim.
enum ReportFunctionalRelationshipsProjectionPolicyV1 {
    static let sectionID = "functional-relationships"
    static let sectionVersion = 1
    static let projectionVersion = "report-functional-relationships-v1"
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let supportedFormats: [ReportProjectionFormatV1] = [.openJSON, .structuredText]
    static let requiredTypedLabels = true
    static let excludesOwnershipAuthorizationComplianceClaims = true
    static let excludesTelemetryAndOperationalClaims = true
    static let excludesRawLocators = true

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }

    static func directionLocalizationKey(
        _ direction: FunctionalRelationshipDirectionV1
    ) -> FunctionalRelationshipLocalizationKeyV1 {
        FunctionalRelationshipLocalizationKeyV1.directionKey(direction)
    }

    static func symmetryLocalizationKey(
        _ symmetry: FunctionalRelationshipSymmetryV1
    ) -> FunctionalRelationshipLocalizationKeyV1 {
        FunctionalRelationshipLocalizationKeyV1.symmetryKey(symmetry)
    }

    static func eventStateLocalizationKey(
        _ action: AssetFunctionalRelationshipEventActionV1
    ) -> FunctionalRelationshipLocalizationKeyV1 {
        FunctionalRelationshipLocalizationKeyV1.eventStateKey(action)
    }

    static func siteLocalizationKey(
        _ policy: FunctionalRelationshipSitePolicyV1
    ) -> FunctionalRelationshipLocalizationKeyV1 {
        FunctionalRelationshipLocalizationKeyV1.sitePolicyKey(policy)
    }

    static func minimumRequirementLocalizationKey(
        _ boundary: FunctionalRelationshipReadinessBoundaryV1
    ) -> FunctionalRelationshipLocalizationKeyV1 {
        FunctionalRelationshipLocalizationKeyV1.minimumRequirementKey(boundary)
    }
}

typealias ReportFunctionalRelationshipProjectionPolicyV1 =
    ReportFunctionalRelationshipsProjectionPolicyV1

// MARK: - C20 audience-safe privacy-transform projection

enum PrivacyTransformReportProjectionFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case redactionNotDeclared
    case projectionDenied(PrivacyProjectionDenialV1)
    case wrongAudience
    case wrongPolicy
    case staleDerivative
    case digestMismatch
    case originalReferenceIncluded
}

/// Metadata-only report binding for an approved privacy derivative.  The
/// original reference, derivative bytes, region coordinates, reviewer actor,
/// and review rationale are intentionally absent from this value.  They stay
/// behind the separately authorized original/content boundary.
struct PrivacyTransformReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let projectionVersion = "privacy-transform-report-v1"

    let schemaVersion: Int
    let projectionVersion: String
    let workspaceID: WorkspaceID
    let manifestID: UUID
    let reviewReceiptID: UUID
    let policyID: UUID
    let audience: EvidenceAudienceV1
    let derivativeContentID: String
    let derivativeSHA256: String
    let sourceRevision: UInt64
    let sourceSHA256: String
    let policyRevision: UInt64
    let policySHA256: String
    let reviewRevision: UInt64
    let reviewSHA256: String
    let reviewDecision: PrivacyReviewDecisionV1
    let staleState: PrivacyTransformStaleStateV1
    let metadataSanitized: Bool
    let redactionDeclared: Bool
    let derivativeOnly: Bool
    let originalReferenceExcluded: Bool
    let transformKinds: [PrivacyTransformKindV1]
    let regionCount: Int
    let projectionSHA256: String

    init(
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        audience: ReportAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        redactionDeclared: Bool = false,
        now: Date = Date()
    ) throws {
        guard let requestedAudience =
            ReportEvidenceAssuranceProjectionPolicyV1.evidenceAudience(for: audience)
        else {
            throw PrivacyTransformReportProjectionFailureV1.wrongAudience
        }
        try self.init(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            redactionDeclared: redactionDeclared,
            now: now
        )
    }

    init(
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        redactionDeclared: Bool = false,
        now: Date = Date()
    ) throws {
        try policy.validate()
        try manifest.validate(policy: policy)
        guard redactionDeclared else {
            throw PrivacyTransformReportProjectionFailureV1.redactionNotDeclared
        }
        let decision = try PrivacyProjectionV1.decide(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            at: now
        )
        guard decision.isAllowed, let derivative = decision.derivative,
              let review,
              review.decision == .approved,
              manifest.staleState == .current,
              manifest.workspaceID == policy.workspaceID,
              manifest.derivative.contentID == derivative.contentID,
              manifest.derivativeSHA256 == derivative.digests.digest(for: .sha256)?.hexadecimalValue,
              manifest.derivativeSHA256 != manifest.sourceSHA256 else {
            throw PrivacyTransformReportProjectionFailureV1.projectionDenied(
                decision.denial ?? .digestMismatch
            )
        }

        let kinds = Array(Set(manifest.orderedRegions.map(\.transformKind)))
            .sorted { $0.rawValue < $1.rawValue }
        schemaVersion = Self.schemaVersion
        projectionVersion = Self.projectionVersion
        workspaceID = manifest.workspaceID
        manifestID = manifest.manifestID
        reviewReceiptID = review.receiptID
        policyID = policy.policyID
        audience = requestedAudience
        derivativeContentID = derivative.contentID
        derivativeSHA256 = manifest.derivativeSHA256
        sourceRevision = manifest.sourceRevision
        sourceSHA256 = manifest.sourceSHA256
        policyRevision = policy.revision
        policySHA256 = policy.policySHA256
        reviewRevision = review.revision
        reviewSHA256 = review.receiptSHA256
        reviewDecision = review.decision
        staleState = manifest.staleState
        metadataSanitized = manifest.metadataSanitation.result == .complete
            && manifest.metadataSanitation.retainedSourceMetadataKeys.isEmpty
        self.redactionDeclared = redactionDeclared
        derivativeOnly = true
        originalReferenceExcluded = true
        transformKinds = kinds
        regionCount = manifest.orderedRegions.count
        projectionSHA256 = try Self.digest(
            workspaceID: workspaceID,
            manifestID: manifestID,
            reviewReceiptID: reviewReceiptID,
            policyID: policyID,
            audience: audience,
            derivativeContentID: derivativeContentID,
            derivativeSHA256: derivativeSHA256,
            sourceRevision: sourceRevision,
            sourceSHA256: sourceSHA256,
            policyRevision: policyRevision,
            policySHA256: policySHA256,
            reviewRevision: reviewRevision,
            reviewSHA256: reviewSHA256,
            reviewDecision: reviewDecision,
            staleState: staleState,
            metadataSanitized: metadataSanitized,
            redactionDeclared: redactionDeclared,
            derivativeOnly: derivativeOnly,
            originalReferenceExcluded: originalReferenceExcluded,
            transformKinds: kinds,
            regionCount: regionCount
        )
        try validate()
    }

    var reportAudience: ReportAudienceV1? {
        switch audience {
        case .internalReview: return .internalUse
        case .customerReport: return .customerSafe
        case .externalCollaborator: return nil
        }
    }

    var isAudienceSafe: Bool {
        derivativeOnly && originalReferenceExcluded && redactionDeclared
            && reviewDecision == .approved && staleState == .current
            && metadataSanitized
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              projectionVersion == Self.projectionVersion,
              workspaceID.rawValue != SearchContractValidationV1.zeroUUID,
              manifestID != SearchContractValidationV1.zeroUUID,
              reviewReceiptID != SearchContractValidationV1.zeroUUID,
              policyID != SearchContractValidationV1.zeroUUID,
              SnapshotProjectionValidationV1.validID(derivativeContentID),
              KernelCanonicalHashV1.validSHA256(derivativeSHA256),
              sourceRevision > 0, sourceRevision <= UInt64(Int.max),
              KernelCanonicalHashV1.validSHA256(sourceSHA256),
              policyRevision > 0, policyRevision <= UInt64(Int.max),
              KernelCanonicalHashV1.validSHA256(policySHA256),
              reviewRevision > 0, reviewRevision <= UInt64(Int.max),
              KernelCanonicalHashV1.validSHA256(reviewSHA256),
              reviewDecision == .approved,
              staleState == .current,
              metadataSanitized,
              redactionDeclared,
              derivativeOnly,
              originalReferenceExcluded,
              !transformKinds.isEmpty,
              transformKinds == transformKinds.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(transformKinds).count == transformKinds.count,
              (1...PrivacyTransformValidationV1.maximumRegions).contains(regionCount),
              projectionSHA256 == expectedDigest else {
            throw PrivacyTransformReportProjectionFailureV1.invalidValue
        }
    }

    static func decide(
        manifest: PrivacyTransformManifestV1?,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        now: Date
    ) throws -> PrivacyProjectionDecisionV1 {
        try PrivacyProjectionV1.decide(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            at: now
        )
    }

    private static func digest(
        workspaceID: WorkspaceID,
        manifestID: UUID,
        reviewReceiptID: UUID,
        policyID: UUID,
        audience: EvidenceAudienceV1,
        derivativeContentID: String,
        derivativeSHA256: String,
        sourceRevision: UInt64,
        sourceSHA256: String,
        policyRevision: UInt64,
        policySHA256: String,
        reviewRevision: UInt64,
        reviewSHA256: String,
        reviewDecision: PrivacyReviewDecisionV1,
        staleState: PrivacyTransformStaleStateV1,
        metadataSanitized: Bool,
        redactionDeclared: Bool,
        derivativeOnly: Bool,
        originalReferenceExcluded: Bool,
        transformKinds: [PrivacyTransformKindV1],
        regionCount: Int
    ) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            projectionVersion: Self.projectionVersion,
            workspaceID: workspaceID,
            manifestID: manifestID,
            reviewReceiptID: reviewReceiptID,
            policyID: policyID,
            audience: audience,
            derivativeContentID: derivativeContentID,
            derivativeSHA256: derivativeSHA256,
            sourceRevision: sourceRevision,
            sourceSHA256: sourceSHA256,
            policyRevision: policyRevision,
            policySHA256: policySHA256,
            reviewRevision: reviewRevision,
            reviewSHA256: reviewSHA256,
            reviewDecision: reviewDecision,
            staleState: staleState,
            metadataSanitized: metadataSanitized,
            redactionDeclared: redactionDeclared,
            derivativeOnly: derivativeOnly,
            originalReferenceExcluded: originalReferenceExcluded,
            transformKinds: transformKinds,
            regionCount: regionCount
        ))
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let projectionVersion: String
        let workspaceID: WorkspaceID
        let manifestID: UUID
        let reviewReceiptID: UUID
        let policyID: UUID
        let audience: EvidenceAudienceV1
        let derivativeContentID: String
        let derivativeSHA256: String
        let sourceRevision: UInt64
        let sourceSHA256: String
        let policyRevision: UInt64
        let policySHA256: String
        let reviewRevision: UInt64
        let reviewSHA256: String
        let reviewDecision: PrivacyReviewDecisionV1
        let staleState: PrivacyTransformStaleStateV1
        let metadataSanitized: Bool
        let redactionDeclared: Bool
        let derivativeOnly: Bool
        let originalReferenceExcluded: Bool
        let transformKinds: [PrivacyTransformKindV1]
        let regionCount: Int
    }
}

typealias AudienceSafeDerivativeProjectionV1 = PrivacyTransformReportProjectionV1
typealias PrivacyTransformAudienceSafeDerivativeProjectionV1 = PrivacyTransformReportProjectionV1

enum PrivacyTransformReportProjectionPolicyV1 {
    static let sectionID = "privacy-transform"
    static let sectionVersion = 1
    static let projectionVersion = PrivacyTransformReportProjectionV1.projectionVersion
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let requiresApprovedReview = true
    static let requiresCurrentDerivative = true
    static let requiresExplicitRedactionDeclaration = true
    static let originalAccessRemainsSeparate = true
    static let historicArtifactsImmutable = true
    static let correctionsAreAmendOnly = true
    static let excludesOriginalReferences = true
    static let excludesOriginalBytes = true
    static let excludesDerivativeBytes = true
    static let excludesReviewerIdentity = true
    static let excludesReviewRationale = true
    static let supportedFormats: [ReportProjectionFormatV1] = [
        .openJSON, .pdf, .structuredText, .media,
    ]

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }
}

/// C13's report-facing assurance envelope.  The envelope is deliberately a
/// projection value rather than a writer or finalization service: a preview
/// is assembled first, an optional immutable manifest records the exact
/// included/excluded links, and local attestations can bind only to that
/// manifest.  No evidence bytes, actor private detail, or delivery state is
/// represented here.
enum ReportEvidenceAssuranceProjectionPolicyV1 {
    static let sectionID = "evidence-assurance"
    static let sectionVersion = 1
    static let projectionVersion = "report-evidence-assurance-v1"
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let publicationDisposition = "PROVISIONAL_READ_ONLY_PRE_S10"
    static let previewRequired = true
    static let manifestRequiredBeforeAttestation = true
    static let excludesEvidenceContent = true
    static let excludesActorPrivateDetail = true
    static let excludesDeliveryAndRelease = true
    static let supportedFormats: [ReportProjectionFormatV1] = [.openJSON, .structuredText]

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }

    static func evidenceAudience(for audience: ReportAudienceV1) -> EvidenceAudienceV1? {
        switch audience {
        case .internalUse: return .internalReview
        case .customerSafe: return .customerReport
        }
    }
}

/// Exact report binding for C13 preview-first evidence publication.  The
/// visibility rows are carried alongside the links so a consumer cannot
/// silently substitute a different audience decision.  Validation is
/// intentionally explicit about stale snapshot/version/purpose/scope inputs.
struct ReportEvidenceAssuranceProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let publicationDisposition = ReportEvidenceAssuranceProjectionPolicyV1.publicationDisposition

    let schemaVersion: Int
    let audience: EvidenceAudienceV1
    let snapshotSHA256: String
    let projectionVersion: String
    let preview: AssuranceProjectionPreviewV1
    let manifest: AssuranceManifestV1?
    let visibilities: [EvidenceVisibilityV1]
    let attestations: [AttestationV1]
    let omissionCount: Int
    let limitationCodes: [EvidenceLimitationV1]
    let publicationDisposition: String

    init(
        preview: AssuranceProjectionPreviewV1,
        manifest: AssuranceManifestV1? = nil,
        visibilities: [EvidenceVisibilityV1],
        attestations: [AttestationV1] = []
    ) throws {
        try preview.validate()
        let orderedVisibilities = visibilities.sorted {
            $0.visibilityID.uuidString.lowercased() < $1.visibilityID.uuidString.lowercased()
        }
        let orderedAttestations = attestations.sorted {
            $0.attestationID.uuidString.lowercased() < $1.attestationID.uuidString.lowercased()
        }
        let excluded = preview.excludedLinks
        let limitations = Array(Set(excluded.map { $0.decision.limitation }))
            .sorted { $0.rawValue < $1.rawValue }
        schemaVersion = Self.schemaVersion
        audience = preview.audience
        snapshotSHA256 = preview.snapshotSHA256
        projectionVersion = preview.projectionVersion
        self.preview = preview
        self.manifest = manifest
        self.visibilities = orderedVisibilities
        self.attestations = orderedAttestations
        omissionCount = excluded.count
        limitationCodes = limitations
        publicationDisposition = Self.publicationDisposition
        try validate()
    }

    func validate(
        expectedSnapshotSHA256: String? = nil,
        expectedProjectionVersion: String? = nil,
        expectedAudience: EvidenceAudienceV1? = nil,
        expectedPurpose: AttestationPurposeV1? = nil,
        expectedScope: AttestationScopeV1? = nil
    ) throws {
        guard schemaVersion == Self.schemaVersion,
              publicationDisposition == Self.publicationDisposition,
              KernelCanonicalHashV1.validSHA256(snapshotSHA256),
              SnapshotProjectionValidationV1.validID(projectionVersion),
              snapshotSHA256 == preview.snapshotSHA256,
              projectionVersion == preview.projectionVersion,
              audience == preview.audience,
              omissionCount == preview.excludedLinks.count,
              limitationCodes == Array(Set(preview.excludedLinks.map { $0.decision.limitation }))
                    .sorted(by: { $0.rawValue < $1.rawValue }),
              visibilities == visibilities.sorted(by: {
                  $0.visibilityID.uuidString.lowercased() < $1.visibilityID.uuidString.lowercased()
              }),
              Set(visibilities.map(\.visibilityID)).count == visibilities.count,
              attestations == attestations.sorted(by: {
                  $0.attestationID.uuidString.lowercased() < $1.attestationID.uuidString.lowercased()
              }),
              Set(attestations.map(\.attestationID)).count == attestations.count else {
            throw EvidenceAssuranceFailureV1.digestMismatch
        }
        try preview.validate()
        var visibilityByID: [UUID: EvidenceVisibilityV1] = [:]
        for visibility in visibilities {
            try visibility.validate()
            guard visibility.workspaceID == preview.workspaceID,
                  visibilityByID.updateValue(visibility, forKey: visibility.visibilityID) == nil else {
                throw EvidenceAssuranceFailureV1.duplicateIdentity
            }
        }
        for link in preview.includedLinks + preview.excludedLinks {
            guard let visibility = visibilityByID[link.visibilityID] else {
                throw EvidenceAssuranceFailureV1.visibilityDenied
            }
            try link.validate(visibility: visibility)
        }
        if let manifest {
            try manifest.validateFresh(preview: preview)
            guard manifest.workspaceID == preview.workspaceID,
                  manifest.audience == audience,
                  manifest.snapshotSHA256 == snapshotSHA256,
                  manifest.projectionVersion == projectionVersion else {
                throw EvidenceAssuranceFailureV1.stalePreview
            }
            guard !attestations.isEmpty || ReportEvidenceAssuranceProjectionPolicyV1
                .manifestRequiredBeforeAttestation else {
                throw EvidenceAssuranceFailureV1.invalidValue
            }
            for attestation in attestations {
                try attestation.validate(manifest: manifest)
                if let expectedPurpose, attestation.purpose != expectedPurpose {
                    throw EvidenceAssuranceFailureV1.invalidValue
                }
                if let expectedScope, attestation.scope != expectedScope {
                    throw EvidenceAssuranceFailureV1.invalidValue
                }
            }
        } else if !attestations.isEmpty {
            throw EvidenceAssuranceFailureV1.invalidValue
        }
        if let expectedSnapshotSHA256, expectedSnapshotSHA256 != snapshotSHA256 {
            throw EvidenceAssuranceFailureV1.stalePreview
        }
        if let expectedProjectionVersion, expectedProjectionVersion != projectionVersion {
            throw EvidenceAssuranceFailureV1.stalePreview
        }
        if let expectedAudience, expectedAudience != audience {
            throw EvidenceAssuranceFailureV1.visibilityDenied
        }
    }
}

struct ReportSectionDefinitionV1: Codable, Equatable, Hashable, Sendable {
    let sectionID: String
    let version: Int
    let required: Bool
    let supportedFormats: [ReportProjectionFormatV1]
    let privacyClass: ReportPrivacyClassV1
    let requiresHeading: Bool
    let requiresTextAlternative: Bool
    let order: Int

    init(
        sectionID: String,
        version: Int,
        required: Bool,
        supportedFormats: [ReportProjectionFormatV1],
        privacyClass: ReportPrivacyClassV1,
        requiresHeading: Bool,
        requiresTextAlternative: Bool,
        order: Int
    ) throws {
        guard SnapshotProjectionValidationV1.validID(sectionID), version > 0, order >= 0,
              !supportedFormats.isEmpty,
              supportedFormats == supportedFormats.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(supportedFormats).count == supportedFormats.count else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        self.sectionID = sectionID
        self.version = version
        self.required = required
        self.supportedFormats = supportedFormats
        self.privacyClass = privacyClass
        self.requiresHeading = requiresHeading
        self.requiresTextAlternative = requiresTextAlternative
        self.order = order
    }

    func validate() throws {
        _ = try Self(
            sectionID: sectionID,
            version: version,
            required: required,
            supportedFormats: supportedFormats,
            privacyClass: privacyClass,
            requiresHeading: requiresHeading,
            requiresTextAlternative: requiresTextAlternative,
            order: order
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sectionID, version, required, supportedFormats, privacyClass
        case requiresHeading, requiresTextAlternative, order
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sectionID: values.decode(String.self, forKey: .sectionID),
            version: values.decode(Int.self, forKey: .version),
            required: values.decode(Bool.self, forKey: .required),
            supportedFormats: values.decode([ReportProjectionFormatV1].self, forKey: .supportedFormats),
            privacyClass: values.decode(ReportPrivacyClassV1.self, forKey: .privacyClass),
            requiresHeading: values.decode(Bool.self, forKey: .requiresHeading),
            requiresTextAlternative: values.decode(Bool.self, forKey: .requiresTextAlternative),
            order: values.decode(Int.self, forKey: .order)
        )
    }
}

struct ReportSectionRegistryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let registryID: String
    let registryVersion: Int
    let sections: [ReportSectionDefinitionV1]

    init(registryID: String, registryVersion: Int, sections: [ReportSectionDefinitionV1]) throws {
        guard SnapshotProjectionValidationV1.validID(registryID), registryVersion > 0,
              !sections.isEmpty,
              sections.map(\.order) == Array(0..<sections.count),
              Set(sections.map(\.sectionID)).count == sections.count,
              sections.filter(\.required).map(\.sectionID).contains("identity"),
              sections.filter(\.required).map(\.sectionID).contains("limitations"),
              sections.filter(\.required).map(\.sectionID).contains("provenance"),
              sections.filter(\.required).map(\.sectionID).contains("supersession"),
              sections.filter(\.required).map(\.sectionID).contains("manifest") else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.registryID = registryID
        self.registryVersion = registryVersion
        self.sections = sections
    }

    var requiredSectionIDs: Set<String> { Set(sections.filter(\.required).map(\.sectionID)) }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        try sections.forEach { try $0.validate() }
        _ = try Self(registryID: registryID, registryVersion: registryVersion, sections: sections)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, registryID, registryVersion, sections
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            registryID: values.decode(String.self, forKey: .registryID),
            registryVersion: values.decode(Int.self, forKey: .registryVersion),
            sections: values.decode([ReportSectionDefinitionV1].self, forKey: .sections)
        )
    }
}

struct ReportLayoutProfileV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let profileID: String
    let profileRelease: Int
    let audience: ReportAudienceV1
    let detail: ReportDetailLevelV1
    let sectionIDs: [String]
    let mediaLayout: ReportMediaLayoutV1
    let orientation: ReportOrientationV1
    let localeIdentifier: String
    let unitsProfileID: String
    let displayProfileID: String

    init(
        profileID: String,
        profileRelease: Int,
        audience: ReportAudienceV1,
        detail: ReportDetailLevelV1,
        sectionIDs: [String],
        mediaLayout: ReportMediaLayoutV1,
        orientation: ReportOrientationV1,
        localeIdentifier: String,
        unitsProfileID: String,
        displayProfileID: String,
        registry: ReportSectionRegistryV1
    ) throws {
        guard SnapshotProjectionValidationV1.validID(profileID), profileRelease > 0,
              SnapshotProjectionValidationV1.validText(localeIdentifier), localeIdentifier.utf8.count <= 64,
              SnapshotProjectionValidationV1.validID(unitsProfileID),
              SnapshotProjectionValidationV1.validID(displayProfileID),
              Set(sectionIDs).count == sectionIDs.count,
              registry.requiredSectionIDs.isSubset(of: Set(sectionIDs)),
              sectionIDs.allSatisfy({ id in registry.sections.contains(where: { $0.sectionID == id }) }),
              sectionIDs == registry.sections.filter({ sectionIDs.contains($0.sectionID) }).map(\.sectionID) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        if audience == .customerSafe,
           sectionIDs.contains(where: { id in registry.sections.first(where: { $0.sectionID == id })?.privacyClass == .internalOnly }) {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        schemaVersion = Self.schemaVersion
        self.profileID = profileID
        self.profileRelease = profileRelease
        self.audience = audience
        self.detail = detail
        self.sectionIDs = sectionIDs
        self.mediaLayout = mediaLayout
        self.orientation = orientation
        self.localeIdentifier = localeIdentifier
        self.unitsProfileID = unitsProfileID
        self.displayProfileID = displayProfileID
    }

    func validate(against registry: ReportSectionRegistryV1) throws {
        guard schemaVersion == Self.schemaVersion else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        try registry.validate()
        _ = try Self(
            profileID: profileID,
            profileRelease: profileRelease,
            audience: audience,
            detail: detail,
            sectionIDs: sectionIDs,
            mediaLayout: mediaLayout,
            orientation: orientation,
            localeIdentifier: localeIdentifier,
            unitsProfileID: unitsProfileID,
            displayProfileID: displayProfileID,
            registry: registry
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, profileID, profileRelease, audience, detail, sectionIDs
        case mediaLayout, orientation, localeIdentifier, unitsProfileID, displayProfileID
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        let profileID = try values.decode(String.self, forKey: .profileID)
        let profileRelease = try values.decode(Int.self, forKey: .profileRelease)
        let sectionIDs = try values.decode([String].self, forKey: .sectionIDs)
        let localeIdentifier = try values.decode(String.self, forKey: .localeIdentifier)
        let unitsProfileID = try values.decode(String.self, forKey: .unitsProfileID)
        let displayProfileID = try values.decode(String.self, forKey: .displayProfileID)
        guard SnapshotProjectionValidationV1.validID(profileID), profileRelease > 0,
              SnapshotProjectionValidationV1.validText(localeIdentifier), localeIdentifier.utf8.count <= 64,
              SnapshotProjectionValidationV1.validID(unitsProfileID),
              SnapshotProjectionValidationV1.validID(displayProfileID),
              Set(sectionIDs).count == sectionIDs.count,
              sectionIDs.allSatisfy(SnapshotProjectionValidationV1.validID) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.profileID = profileID
        self.profileRelease = profileRelease
        audience = try values.decode(ReportAudienceV1.self, forKey: .audience)
        detail = try values.decode(ReportDetailLevelV1.self, forKey: .detail)
        self.sectionIDs = sectionIDs
        mediaLayout = try values.decode(ReportMediaLayoutV1.self, forKey: .mediaLayout)
        orientation = try values.decode(ReportOrientationV1.self, forKey: .orientation)
        self.localeIdentifier = localeIdentifier
        self.unitsProfileID = unitsProfileID
        self.displayProfileID = displayProfileID
    }
}

struct ExportProfileV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let exportProfileID: String
    let exportProfileRelease: Int
    let formats: [ReportProjectionFormatV1]
    let packaging: ReportPackagingV1
    let privacyTransformID: String
    let maximumMediaItems: Int
    let maximumArchiveBytes: Int64

    init(
        exportProfileID: String,
        exportProfileRelease: Int,
        formats: [ReportProjectionFormatV1],
        packaging: ReportPackagingV1,
        privacyTransformID: String,
        maximumMediaItems: Int,
        maximumArchiveBytes: Int64
    ) throws {
        guard SnapshotProjectionValidationV1.validID(exportProfileID), exportProfileRelease > 0,
              !formats.isEmpty, formats == formats.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(formats).count == formats.count,
              formats.contains(.pdf), formats.contains(.openJSON), formats.contains(.structuredText),
              SnapshotProjectionValidationV1.validID(privacyTransformID),
              (0...256).contains(maximumMediaItems),
              (1...Int64(SnapshotProjectionLimitsV1.maximumProjectionBytes)).contains(maximumArchiveBytes) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.exportProfileID = exportProfileID
        self.exportProfileRelease = exportProfileRelease
        self.formats = formats
        self.packaging = packaging
        self.privacyTransformID = privacyTransformID
        self.maximumMediaItems = maximumMediaItems
        self.maximumArchiveBytes = maximumArchiveBytes
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        _ = try Self(
            exportProfileID: exportProfileID,
            exportProfileRelease: exportProfileRelease,
            formats: formats,
            packaging: packaging,
            privacyTransformID: privacyTransformID,
            maximumMediaItems: maximumMediaItems,
            maximumArchiveBytes: maximumArchiveBytes
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, exportProfileID, exportProfileRelease, formats, packaging
        case privacyTransformID, maximumMediaItems, maximumArchiveBytes
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            exportProfileID: values.decode(String.self, forKey: .exportProfileID),
            exportProfileRelease: values.decode(Int.self, forKey: .exportProfileRelease),
            formats: values.decode([ReportProjectionFormatV1].self, forKey: .formats),
            packaging: values.decode(ReportPackagingV1.self, forKey: .packaging),
            privacyTransformID: values.decode(String.self, forKey: .privacyTransformID),
            maximumMediaItems: values.decode(Int.self, forKey: .maximumMediaItems),
            maximumArchiveBytes: values.decode(Int64.self, forKey: .maximumArchiveBytes)
        )
    }
}

struct FinalizedReportProfileBindingV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: String
    let snapshotID: String
    let outputScopeID: String
    let reportProfileID: String
    let reportProfileRelease: Int
    let reportProfileSHA256: String
    let exportProfileID: String
    let exportProfileRelease: Int
    let exportProfileSHA256: String
    let sectionRegistryID: String
    let sectionRegistryVersion: Int
    let sectionRegistrySHA256: String
    let contractManifestID: String
    let contractManifestVersion: Int
    let contractManifestSHA256: String
    let sectionIDs: [String]
    let audience: ReportAudienceV1
    let detail: ReportDetailLevelV1
    let privacyTransformID: String
    let localeIdentifier: String
    let unitsProfileID: String
    let displayProfileID: String
    let orientation: ReportOrientationV1
    let mediaLayout: ReportMediaLayoutV1
    let rendererVersion: String
    let projectionVersion: String

    init(
        workspaceID: String,
        snapshotID: String,
        outputScopeID: String,
        reportProfileID: String,
        reportProfileRelease: Int,
        reportProfileSHA256: String,
        exportProfileID: String,
        exportProfileRelease: Int,
        exportProfileSHA256: String,
        sectionRegistryID: String,
        sectionRegistryVersion: Int,
        sectionRegistrySHA256: String,
        contractManifestID: String,
        contractManifestVersion: Int,
        contractManifestSHA256: String,
        sectionIDs: [String],
        audience: ReportAudienceV1,
        detail: ReportDetailLevelV1,
        privacyTransformID: String,
        localeIdentifier: String,
        unitsProfileID: String,
        displayProfileID: String,
        orientation: ReportOrientationV1,
        mediaLayout: ReportMediaLayoutV1,
        rendererVersion: String,
        projectionVersion: String
    ) throws {
        let ids = [workspaceID, snapshotID, outputScopeID, reportProfileID, exportProfileID,
                   sectionRegistryID, contractManifestID, privacyTransformID, unitsProfileID,
                   displayProfileID, rendererVersion, projectionVersion]
        guard ids.allSatisfy(SnapshotProjectionValidationV1.validID),
              reportProfileRelease > 0, exportProfileRelease > 0, sectionRegistryVersion > 0,
              contractManifestVersion > 0,
              [reportProfileSHA256, exportProfileSHA256, sectionRegistrySHA256, contractManifestSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),
              !sectionIDs.isEmpty, Set(sectionIDs).count == sectionIDs.count,
              sectionIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              SnapshotProjectionValidationV1.validText(localeIdentifier), localeIdentifier.utf8.count <= 64 else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.snapshotID = snapshotID
        self.outputScopeID = outputScopeID
        self.reportProfileID = reportProfileID
        self.reportProfileRelease = reportProfileRelease
        self.reportProfileSHA256 = reportProfileSHA256
        self.exportProfileID = exportProfileID
        self.exportProfileRelease = exportProfileRelease
        self.exportProfileSHA256 = exportProfileSHA256
        self.sectionRegistryID = sectionRegistryID
        self.sectionRegistryVersion = sectionRegistryVersion
        self.sectionRegistrySHA256 = sectionRegistrySHA256
        self.contractManifestID = contractManifestID
        self.contractManifestVersion = contractManifestVersion
        self.contractManifestSHA256 = contractManifestSHA256
        self.sectionIDs = sectionIDs
        self.audience = audience
        self.detail = detail
        self.privacyTransformID = privacyTransformID
        self.localeIdentifier = localeIdentifier
        self.unitsProfileID = unitsProfileID
        self.displayProfileID = displayProfileID
        self.orientation = orientation
        self.mediaLayout = mediaLayout
        self.rendererVersion = rendererVersion
        self.projectionVersion = projectionVersion
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        _ = try Self(
            workspaceID: workspaceID,
            snapshotID: snapshotID,
            outputScopeID: outputScopeID,
            reportProfileID: reportProfileID,
            reportProfileRelease: reportProfileRelease,
            reportProfileSHA256: reportProfileSHA256,
            exportProfileID: exportProfileID,
            exportProfileRelease: exportProfileRelease,
            exportProfileSHA256: exportProfileSHA256,
            sectionRegistryID: sectionRegistryID,
            sectionRegistryVersion: sectionRegistryVersion,
            sectionRegistrySHA256: sectionRegistrySHA256,
            contractManifestID: contractManifestID,
            contractManifestVersion: contractManifestVersion,
            contractManifestSHA256: contractManifestSHA256,
            sectionIDs: sectionIDs,
            audience: audience,
            detail: detail,
            privacyTransformID: privacyTransformID,
            localeIdentifier: localeIdentifier,
            unitsProfileID: unitsProfileID,
            displayProfileID: displayProfileID,
            orientation: orientation,
            mediaLayout: mediaLayout,
            rendererVersion: rendererVersion,
            projectionVersion: projectionVersion
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, snapshotID, outputScopeID, reportProfileID, reportProfileRelease
        case reportProfileSHA256, exportProfileID, exportProfileRelease, exportProfileSHA256
        case sectionRegistryID, sectionRegistryVersion, sectionRegistrySHA256, contractManifestID
        case contractManifestVersion, contractManifestSHA256, sectionIDs, audience, detail, privacyTransformID
        case localeIdentifier, unitsProfileID, displayProfileID, orientation, mediaLayout, rendererVersion, projectionVersion
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try self.init(
            workspaceID: values.decode(String.self, forKey: .workspaceID),
            snapshotID: values.decode(String.self, forKey: .snapshotID),
            outputScopeID: values.decode(String.self, forKey: .outputScopeID),
            reportProfileID: values.decode(String.self, forKey: .reportProfileID),
            reportProfileRelease: values.decode(Int.self, forKey: .reportProfileRelease),
            reportProfileSHA256: values.decode(String.self, forKey: .reportProfileSHA256),
            exportProfileID: values.decode(String.self, forKey: .exportProfileID),
            exportProfileRelease: values.decode(Int.self, forKey: .exportProfileRelease),
            exportProfileSHA256: values.decode(String.self, forKey: .exportProfileSHA256),
            sectionRegistryID: values.decode(String.self, forKey: .sectionRegistryID),
            sectionRegistryVersion: values.decode(Int.self, forKey: .sectionRegistryVersion),
            sectionRegistrySHA256: values.decode(String.self, forKey: .sectionRegistrySHA256),
            contractManifestID: values.decode(String.self, forKey: .contractManifestID),
            contractManifestVersion: values.decode(Int.self, forKey: .contractManifestVersion),
            contractManifestSHA256: values.decode(String.self, forKey: .contractManifestSHA256),
            sectionIDs: values.decode([String].self, forKey: .sectionIDs),
            audience: values.decode(ReportAudienceV1.self, forKey: .audience),
            detail: values.decode(ReportDetailLevelV1.self, forKey: .detail),
            privacyTransformID: values.decode(String.self, forKey: .privacyTransformID),
            localeIdentifier: values.decode(String.self, forKey: .localeIdentifier),
            unitsProfileID: values.decode(String.self, forKey: .unitsProfileID),
            displayProfileID: values.decode(String.self, forKey: .displayProfileID),
            orientation: values.decode(ReportOrientationV1.self, forKey: .orientation),
            mediaLayout: values.decode(ReportMediaLayoutV1.self, forKey: .mediaLayout),
            rendererVersion: values.decode(String.self, forKey: .rendererVersion),
            projectionVersion: values.decode(String.self, forKey: .projectionVersion)
        )
    }
}

struct ReportPreviewProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let previewID: String
    let sourceRevision: Int
    let profileSHA256: String
    let markedPreview: Bool
    let hasReportEffect: Bool
    let hasMetricEffect: Bool
    let hasShareEffect: Bool

    init(previewID: String, sourceRevision: Int, profileSHA256: String) throws {
        guard SnapshotProjectionValidationV1.validID(previewID), sourceRevision > 0,
              KernelCanonicalHashV1.validSHA256(profileSHA256) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.previewID = previewID
        self.sourceRevision = sourceRevision
        self.profileSHA256 = profileSHA256
        markedPreview = true
        hasReportEffect = false
        hasMetricEffect = false
        hasShareEffect = false
    }

    func isStale(currentSourceRevision: Int, currentProfileSHA256: String) -> Bool {
        sourceRevision != currentSourceRevision || profileSHA256 != currentProfileSHA256
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        _ = try Self(previewID: previewID, sourceRevision: sourceRevision, profileSHA256: profileSHA256)
        guard markedPreview, !hasReportEffect, !hasMetricEffect, !hasShareEffect else {
            throw SnapshotProjectionFailureV1.partialEffect
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, previewID, sourceRevision, profileSHA256, markedPreview
        case hasReportEffect, hasMetricEffect, hasShareEffect
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        let reconstructed = try Self(
            previewID: values.decode(String.self, forKey: .previewID),
            sourceRevision: values.decode(Int.self, forKey: .sourceRevision),
            profileSHA256: values.decode(String.self, forKey: .profileSHA256)
        )
        guard try values.decode(Bool.self, forKey: .markedPreview) == reconstructed.markedPreview,
              values.decode(Bool.self, forKey: .hasReportEffect) == reconstructed.hasReportEffect,
              values.decode(Bool.self, forKey: .hasMetricEffect) == reconstructed.hasMetricEffect,
              values.decode(Bool.self, forKey: .hasShareEffect) == reconstructed.hasShareEffect else {
            throw SnapshotProjectionFailureV1.partialEffect
        }
        self = reconstructed
    }
}

struct OutputScopedContentReferenceV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let outputScopeID: String
    let outputReferenceID: String
    let workspaceBindingSHA256: String
    let contentSHA256: String
    let mediaType: String
    let byteRole: ContentByteRoleV1

    static func < (lhs: OutputScopedContentReferenceV1, rhs: OutputScopedContentReferenceV1) -> Bool {
        lhs.outputReferenceID < rhs.outputReferenceID
    }

    init(outputScopeID: String, ordinal: Int, reference: ContentReferenceV1) throws {
        guard SnapshotProjectionValidationV1.validID(outputScopeID),
              (0...999).contains(ordinal),
              let sha256 = reference.digests.digest(for: .sha256)?.hexadecimalValue else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        let workspaceBindingSHA256 = KernelCanonicalHashV1.sha256(
            Data("\(reference.workspaceID)|\(outputScopeID)".utf8)
        )
        let namespace = KernelCanonicalHashV1.sha256(Data("\(reference.workspaceID)|\(outputScopeID)|\(sha256)".utf8))
        self.outputScopeID = outputScopeID
        outputReferenceID = "out-\(namespace.prefix(16))-\(String(format: "%03d", ordinal))"
        self.workspaceBindingSHA256 = workspaceBindingSHA256
        contentSHA256 = sha256
        mediaType = reference.mediaType
        byteRole = reference.byteRole
    }

    func validate() throws {
        let identity = Array(outputReferenceID.utf8)
        let lowercaseHex = identity.dropFirst(4).prefix(16)
        let ordinal = identity.suffix(3)
        guard SnapshotProjectionValidationV1.validID(outputScopeID),
              identity.count == 24,
              identity.starts(with: Array("out-".utf8)),
              identity[20] == 0x2D,
              lowercaseHex.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }),
              ordinal.allSatisfy({ (0x30...0x39).contains($0) }),
              KernelCanonicalHashV1.validSHA256(workspaceBindingSHA256),
              KernelCanonicalHashV1.validSHA256(contentSHA256),
              ContentContractValidationV1.validMediaType(mediaType) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case outputScopeID, outputReferenceID, workspaceBindingSHA256, contentSHA256, mediaType, byteRole
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        outputScopeID = try values.decode(String.self, forKey: .outputScopeID)
        outputReferenceID = try values.decode(String.self, forKey: .outputReferenceID)
        workspaceBindingSHA256 = try values.decode(String.self, forKey: .workspaceBindingSHA256)
        contentSHA256 = try values.decode(String.self, forKey: .contentSHA256)
        mediaType = try values.decode(String.self, forKey: .mediaType)
        byteRole = try values.decode(ContentByteRoleV1.self, forKey: .byteRole)
        try validate()
    }
}

// MARK: - C14 inspection review projection

/// C14's report section is a typed, read-only history projection.  Reasons,
/// actor snapshots, private assignment details, and evidence content remain
/// out of this public semantic surface; exact facts and their digests stay
/// available in the completed-snapshot contract.
enum ReportInspectionReviewHistoryProjectionPolicyV1 {
    static let sectionID = "inspection-review-history"
    static let sectionVersion = 1
    static let projectionVersion = "report-inspection-review-history-v1"
    static let requiredTypedLabels = true
    static let excludesClaims = true
    static let excludesTelemetry = true
    static let excludesOwnershipAndAuthorization = true
    static let excludesActorPrivateDetail = true
    static let supportsOpenJSON = true
    static let supportsStructuredText = true

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        switch format {
        case .openJSON, .structuredText: return true
        default: return false
        }
    }
}

struct ReportInspectionReviewHistoryProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let projectionVersion: String
    let sourceSnapshotSHA256: String
    let historySnapshotSHA256: String
    let bindingSHA256: String
    let reviewTransitionIDs: [String]
    let reviewStateLabels: [String]
    let reviewDispositionIDs: [String]
    let reviewDispositionLabels: [String]
    let changeRequestRevisionIDs: [String]
    let changeStateLabels: [String]
    let actionEventIDs: [String]
    let actionStateLabels: [String]

    var reviewCount: Int { reviewTransitionIDs.count + reviewDispositionIDs.count }
    var changeCount: Int { changeRequestRevisionIDs.count }
    var actionCount: Int { actionEventIDs.count }

    init(history: CompletedInspectionReviewHistorySnapshotV1) throws {
        try history.validate()
        schemaVersion = Self.schemaVersion
        projectionVersion = ReportInspectionReviewHistoryProjectionPolicyV1.projectionVersion
        sourceSnapshotSHA256 = history.sourceSnapshotSHA256
        historySnapshotSHA256 = history.snapshotSHA256
        bindingSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            projectionVersion: projectionVersion,
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            historySnapshotSHA256: historySnapshotSHA256,
            reviewTransitionIDs: history.reviewTransitions.map { $0.transitionID.uuidString.lowercased() },
            reviewStateLabels: history.reviewTransitions.map { $0.toState.rawValue },
            reviewDispositionIDs: history.reviewDispositions.map { $0.dispositionID.uuidString.lowercased() },
            reviewDispositionLabels: history.reviewDispositions.map { $0.kind.rawValue },
            changeRequestRevisionIDs: history.changeRequests.map { $0.requestRevisionID.uuidString.lowercased() },
            changeStateLabels: history.changeRequests.map { $0.state.rawValue },
            actionEventIDs: history.correctiveActions.map { $0.eventID.uuidString.lowercased() },
            actionStateLabels: history.correctiveActions.map { $0.state.rawValue }
        ))
        reviewTransitionIDs = history.reviewTransitions.map { $0.transitionID.uuidString.lowercased() }
        reviewStateLabels = history.reviewTransitions.map { $0.toState.rawValue }
        reviewDispositionIDs = history.reviewDispositions.map { $0.dispositionID.uuidString.lowercased() }
        reviewDispositionLabels = history.reviewDispositions.map { $0.kind.rawValue }
        changeRequestRevisionIDs = history.changeRequests.map { $0.requestRevisionID.uuidString.lowercased() }
        changeStateLabels = history.changeRequests.map { $0.state.rawValue }
        actionEventIDs = history.correctiveActions.map { $0.eventID.uuidString.lowercased() }
        actionStateLabels = history.correctiveActions.map { $0.state.rawValue }
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              projectionVersion == ReportInspectionReviewHistoryProjectionPolicyV1.projectionVersion,
              KernelCanonicalHashV1.validSHA256(sourceSnapshotSHA256),
              KernelCanonicalHashV1.validSHA256(historySnapshotSHA256),
              KernelCanonicalHashV1.validSHA256(bindingSHA256),
              reviewTransitionIDs.count == reviewStateLabels.count,
              reviewDispositionIDs.count == reviewDispositionLabels.count,
              changeRequestRevisionIDs.count == changeStateLabels.count,
              actionEventIDs.count == actionStateLabels.count,
              reviewTransitionIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              reviewDispositionIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              changeRequestRevisionIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              actionEventIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              reviewTransitionIDs == reviewTransitionIDs.sorted(),
              reviewDispositionIDs == reviewDispositionIDs.sorted(),
              changeRequestRevisionIDs == changeRequestRevisionIDs.sorted(),
              actionEventIDs == actionEventIDs.sorted(),
              Set(reviewTransitionIDs).count == reviewTransitionIDs.count,
              Set(reviewDispositionIDs).count == reviewDispositionIDs.count,
              Set(changeRequestRevisionIDs).count == changeRequestRevisionIDs.count,
              Set(actionEventIDs).count == actionEventIDs.count,
              reviewStateLabels.allSatisfy(SnapshotProjectionValidationV1.validText),
              reviewDispositionLabels.allSatisfy(SnapshotProjectionValidationV1.validText),
              changeStateLabels.allSatisfy(SnapshotProjectionValidationV1.validText),
              actionStateLabels.allSatisfy(SnapshotProjectionValidationV1.validText) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        let expected = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: schemaVersion,
            projectionVersion: projectionVersion,
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            historySnapshotSHA256: historySnapshotSHA256,
            reviewTransitionIDs: reviewTransitionIDs,
            reviewStateLabels: reviewStateLabels,
            reviewDispositionIDs: reviewDispositionIDs,
            reviewDispositionLabels: reviewDispositionLabels,
            changeRequestRevisionIDs: changeRequestRevisionIDs,
            changeStateLabels: changeStateLabels,
            actionEventIDs: actionEventIDs,
            actionStateLabels: actionStateLabels
        ))
        guard bindingSHA256 == expected else { throw SnapshotProjectionFailureV1.digestMismatch }
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let projectionVersion: String
        let sourceSnapshotSHA256: String
        let historySnapshotSHA256: String
        let reviewTransitionIDs: [String]
        let reviewStateLabels: [String]
        let reviewDispositionIDs: [String]
        let reviewDispositionLabels: [String]
        let changeRequestRevisionIDs: [String]
        let changeStateLabels: [String]
        let actionEventIDs: [String]
        let actionStateLabels: [String]
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, projectionVersion, sourceSnapshotSHA256
        case historySnapshotSHA256, bindingSHA256, reviewTransitionIDs
        case reviewStateLabels, reviewDispositionIDs, reviewDispositionLabels
        case changeRequestRevisionIDs, changeStateLabels, actionEventIDs
        case actionStateLabels
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // The projection's public wire form is deliberately decoded directly;
        // no private actor/reason data is needed to validate a report copy.
        self.schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        self.projectionVersion = try values.decode(String.self, forKey: .projectionVersion)
        self.sourceSnapshotSHA256 = try values.decode(String.self, forKey: .sourceSnapshotSHA256)
        self.historySnapshotSHA256 = try values.decode(String.self, forKey: .historySnapshotSHA256)
        self.bindingSHA256 = try values.decode(String.self, forKey: .bindingSHA256)
        self.reviewTransitionIDs = try values.decode([String].self, forKey: .reviewTransitionIDs)
        self.reviewStateLabels = try values.decode([String].self, forKey: .reviewStateLabels)
        self.reviewDispositionIDs = try values.decode([String].self, forKey: .reviewDispositionIDs)
        self.reviewDispositionLabels = try values.decode([String].self, forKey: .reviewDispositionLabels)
        self.changeRequestRevisionIDs = try values.decode([String].self, forKey: .changeRequestRevisionIDs)
        self.changeStateLabels = try values.decode([String].self, forKey: .changeStateLabels)
        self.actionEventIDs = try values.decode([String].self, forKey: .actionEventIDs)
        self.actionStateLabels = try values.decode([String].self, forKey: .actionStateLabels)
        try validate()
    }
}

typealias ReportReviewChangeActionHistoryProjectionV1 = ReportInspectionReviewHistoryProjectionV1

// MARK: - C15 work-packet report projection

/// C15 exposes only bounded, customer-safe packet coordination facts. The
/// canonical packet event rows, actor snapshots, result/evidence links, and
/// collision digests remain in the completed snapshot and are never copied to
/// this report DTO.
enum ReportWorkPacketProjectionPolicyV1 {
    static let sectionID = "work-packet"
    static let sectionVersion = 1
    static let projectionVersion = "report-work-packet-v1"
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let publicationDisposition = "PROVISIONAL_READ_ONLY_PRE_S10"
    static let requiredTypedLabels = true
    static let indexesCurrentHeadsOnly = true
    static let excludesActorPrivateDetail = true
    static let excludesResultAndEvidenceLinks = true
    static let excludesClaimsAndAuthorization = true
    static let excludesTelemetryAndDelivery = true
    static let supportedFormats: [ReportProjectionFormatV1] = [.openJSON, .structuredText]

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }
}

struct ReportWorkPacketProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let projectionVersion: String
    let sourceSnapshotSHA256: String
    let packetID: UUID
    let manifestSHA256: String
    let itemCount: Int
    let itemIDs: [String]
    let itemStateLabels: [String]
    let preservedResultCount: Int
    let collisionCount: Int
    let historyEventCount: Int
    let bindingSHA256: String

    init(
        snapshot: CompletedWorkPacketSnapshotV1,
        sourceSnapshotSHA256: String
    ) throws {
        try snapshot.validate()
        guard KernelCanonicalHashV1.validSHA256(sourceSnapshotSHA256) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        let ordered = snapshot.items.sorted { $0.itemID < $1.itemID }
        let ids = ordered.map(\.itemID)
        let states = ordered.map(\.state.rawValue)
        let resultCount = ordered.reduce(0) { $0 + $1.preservedResultCount }
        let collisionCount = ordered.reduce(0) { $0 + $1.conflictKinds.count }
        let historyCount = snapshot.claims.count + snapshot.leases.count
            + snapshot.releases.count + snapshot.handoffs.count
        let binding = try Self.binding(
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            packetID: snapshot.manifest.packetID,
            manifestSHA256: snapshot.manifest.manifestSHA256,
            itemCount: ordered.count,
            itemIDs: ids,
            itemStateLabels: states,
            preservedResultCount: resultCount,
            collisionCount: collisionCount,
            historyEventCount: historyCount
        )
        self.init(
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            packetID: snapshot.manifest.packetID,
            manifestSHA256: snapshot.manifest.manifestSHA256,
            itemCount: ordered.count,
            itemIDs: ids,
            itemStateLabels: states,
            preservedResultCount: resultCount,
            collisionCount: collisionCount,
            historyEventCount: historyCount,
            bindingSHA256: binding
        )
    }

    private init(
        sourceSnapshotSHA256: String,
        packetID: UUID,
        manifestSHA256: String,
        itemCount: Int,
        itemIDs: [String],
        itemStateLabels: [String],
        preservedResultCount: Int,
        collisionCount: Int,
        historyEventCount: Int,
        bindingSHA256: String
    ) {
        schemaVersion = Self.schemaVersion
        projectionVersion = ReportWorkPacketProjectionPolicyV1.projectionVersion
        self.sourceSnapshotSHA256 = sourceSnapshotSHA256
        self.packetID = packetID
        self.manifestSHA256 = manifestSHA256
        self.itemCount = itemCount
        self.itemIDs = itemIDs
        self.itemStateLabels = itemStateLabels
        self.preservedResultCount = preservedResultCount
        self.collisionCount = collisionCount
        self.historyEventCount = historyEventCount
        self.bindingSHA256 = bindingSHA256
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              projectionVersion == ReportWorkPacketProjectionPolicyV1.projectionVersion,
              KernelCanonicalHashV1.validSHA256(sourceSnapshotSHA256),
              packetID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              KernelCanonicalHashV1.validSHA256(manifestSHA256),
              itemCount > 0,
              itemIDs.count == itemCount,
              itemStateLabels.count == itemCount,
              itemIDs == itemIDs.sorted(),
              Set(itemIDs).count == itemIDs.count,
              itemIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              itemStateLabels.allSatisfy {
                  CompletedWorkPacketItemStateV1(rawValue: $0) != nil
              },
              preservedResultCount >= 0,
              collisionCount >= 0,
              historyEventCount >= 0,
              KernelCanonicalHashV1.validSHA256(bindingSHA256) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        let expected = try Self.binding(
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            packetID: packetID,
            manifestSHA256: manifestSHA256,
            itemCount: itemCount,
            itemIDs: itemIDs,
            itemStateLabels: itemStateLabels,
            preservedResultCount: preservedResultCount,
            collisionCount: collisionCount,
            historyEventCount: historyEventCount
        )
        guard expected == bindingSHA256 else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
    }

    private static func binding(
        sourceSnapshotSHA256: String,
        packetID: UUID,
        manifestSHA256: String,
        itemCount: Int,
        itemIDs: [String],
        itemStateLabels: [String],
        preservedResultCount: Int,
        collisionCount: Int,
        historyEventCount: Int
    ) throws -> String {
        KernelCanonicalHashV1.sha256(try WorkspaceMutationCanonicalV1.data(Basis(
            schemaVersion: Self.schemaVersion,
            projectionVersion: ReportWorkPacketProjectionPolicyV1.projectionVersion,
            sourceSnapshotSHA256: sourceSnapshotSHA256,
            packetID: packetID,
            manifestSHA256: manifestSHA256,
            itemCount: itemCount,
            itemIDs: itemIDs,
            itemStateLabels: itemStateLabels,
            preservedResultCount: preservedResultCount,
            collisionCount: collisionCount,
            historyEventCount: historyEventCount
        )))
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let projectionVersion: String
        let sourceSnapshotSHA256: String
        let packetID: UUID
        let manifestSHA256: String
        let itemCount: Int
        let itemIDs: [String]
        let itemStateLabels: [String]
        let preservedResultCount: Int
        let collisionCount: Int
        let historyEventCount: Int
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, projectionVersion, sourceSnapshotSHA256, packetID
        case manifestSHA256, itemCount, itemIDs, itemStateLabels
        case preservedResultCount, collisionCount, historyEventCount, bindingSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sourceSnapshotSHA256: values.decode(String.self, forKey: .sourceSnapshotSHA256),
            packetID: values.decode(UUID.self, forKey: .packetID),
            manifestSHA256: values.decode(String.self, forKey: .manifestSHA256),
            itemCount: values.decode(Int.self, forKey: .itemCount),
            itemIDs: values.decode([String].self, forKey: .itemIDs),
            itemStateLabels: values.decode([String].self, forKey: .itemStateLabels),
            preservedResultCount: values.decode(Int.self, forKey: .preservedResultCount),
            collisionCount: values.decode(Int.self, forKey: .collisionCount),
            historyEventCount: values.decode(Int.self, forKey: .historyEventCount),
            bindingSHA256: values.decode(String.self, forKey: .bindingSHA256)
        )
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try values.decode(String.self, forKey: .projectionVersion)
                    == ReportWorkPacketProjectionPolicyV1.projectionVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try validate()
    }
}

// MARK: - C21 client capability and package lifecycle projection

enum ClientCapabilityReportProjectionFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case admissionDenied
    case operationMismatch
    case wrongWorkspace
    case digestMismatch
    case unknownLifecycleValue
    case identityLeak
}

/// Metadata-only report binding for local capability admission and package
/// lifecycle disposition.  The canonical profile, policy, disposition, and
/// decision remain the source of truth; this value carries only bounded IDs,
/// digests, closed values, and deterministic operation permissions.
struct ClientCapabilityReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let projectionVersion = "client-capability-report-v1"

    let schemaVersion: Int
    let projectionVersion: String
    let workspaceID: WorkspaceID
    let decisionID: UUID
    let profileID: UUID
    let policyID: UUID
    let dispositionID: UUID
    let packageReleaseID: String
    let packageSHA256: String
    let workflowSHA256: String
    let profileRevision: UInt64
    let policyRevision: UInt64
    let dispositionRevision: UInt64
    let decisionRevision: UInt64
    let profileSHA256: String
    let policySHA256: String
    let dispositionSHA256: String
    let decisionSHA256: String
    let operation: PackageLifecycleOperationV1
    let admission: ClientAdmissionV1
    let lifecycleState: PackageLifecycleStateV1
    let reasons: [ClientCapabilityReasonV1]
    let readAllowed: Bool
    let writeAllowed: Bool
    let operationAllowed: Bool
    let historicArtifact: Bool
    let historicExportAllowed: Bool
    let immutableHistoric: Bool
    let projectionSHA256: String

    init(
        decision: ClientCapabilityAdmissionDecisionV1,
        profile: ClientCapabilityProfileV1,
        policy: PackageLifecyclePolicyV1,
        disposition: PackageLifecycleDispositionV1,
        release: InspectionPackageReleaseV1
    ) throws {
        try decision.validate(
            profile: profile,
            policy: policy,
            disposition: disposition,
            release: release
        )
        let expected = ClientCapabilityAdmissionEvaluatorV1.evaluate(
            profile: profile,
            policy: policy,
            disposition: disposition,
            release: release,
            operation: decision.operation
        )
        guard decision.admission == expected.0,
              decision.reasons == expected.1.sorted(by: { $0.rawValue < $1.rawValue }),
              decision.workspaceID == profile.workspaceID,
              profile.workspaceID == policy.workspaceID,
              policy.workspaceID == disposition.workspaceID,
              decision.packageReleaseID == release.packageReleaseID,
              decision.packageSHA256 == release.packageSHA256,
              decision.workflowSHA256 == release.workflowSHA256 else {
            throw ClientCapabilityReportProjectionFailureV1.admissionDenied
        }

        let readAllowed = decision.admission == .readWrite
            || decision.admission == .readOnly
        let operationAllowed = Self.readOperations.contains(decision.operation)
            ? readAllowed
            : Self.writeOperations.contains(decision.operation)
                && decision.admission == .readWrite
        let writeAllowed = decision.admission == .readWrite
            && Self.writeOperations.contains(decision.operation)
        let historicArtifact = disposition.state == .withdrawn
        let historicExportAllowed = historicArtifact
            && readAllowed
            && decision.operation == .export
            && Self.readOperations.contains(decision.operation)

        schemaVersion = Self.schemaVersion
        projectionVersion = Self.projectionVersion
        workspaceID = decision.workspaceID
        decisionID = decision.decisionID
        profileID = profile.profileID
        policyID = policy.policyID
        dispositionID = disposition.dispositionID
        packageReleaseID = release.packageReleaseID
        packageSHA256 = release.packageSHA256
        workflowSHA256 = release.workflowSHA256
        profileRevision = profile.revision
        policyRevision = policy.revision
        dispositionRevision = disposition.revision
        decisionRevision = decision.revision
        profileSHA256 = profile.profileSHA256
        policySHA256 = policy.policySHA256
        dispositionSHA256 = disposition.dispositionSHA256
        decisionSHA256 = decision.decisionSHA256
        operation = decision.operation
        admission = decision.admission
        lifecycleState = disposition.state
        reasons = decision.reasons
        self.readAllowed = readAllowed
        self.writeAllowed = writeAllowed
        self.operationAllowed = operationAllowed
        self.historicArtifact = historicArtifact
        self.historicExportAllowed = historicExportAllowed
        immutableHistoric = true
        projectionSHA256 = try Self.digest(
            workspaceID: workspaceID,
            decisionID: decisionID,
            profileID: profileID,
            policyID: policyID,
            dispositionID: dispositionID,
            packageReleaseID: packageReleaseID,
            packageSHA256: packageSHA256,
            workflowSHA256: workflowSHA256,
            profileRevision: profileRevision,
            policyRevision: policyRevision,
            dispositionRevision: dispositionRevision,
            decisionRevision: decisionRevision,
            profileSHA256: profileSHA256,
            policySHA256: policySHA256,
            dispositionSHA256: dispositionSHA256,
            decisionSHA256: decisionSHA256,
            operation: operation,
            admission: admission,
            lifecycleState: lifecycleState,
            reasons: reasons,
            readAllowed: readAllowed,
            writeAllowed: writeAllowed,
            operationAllowed: operationAllowed,
            historicArtifact: historicArtifact,
            historicExportAllowed: historicExportAllowed,
            immutableHistoric: immutableHistoric
        )
        try validate()
    }

    var startsNewWorkAllowed: Bool {
        writeAllowed && operation == .start
    }

    var isReadOnly: Bool {
        admission == .readOnly
    }

    var isDenied: Bool {
        admission == .migrationRequired
            || admission == .quarantine
            || admission == .reject
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              projectionVersion == Self.projectionVersion,
              workspaceID.rawValue != SearchContractValidationV1.zeroUUID,
              decisionID != SearchContractValidationV1.zeroUUID,
              profileID != SearchContractValidationV1.zeroUUID,
              policyID != SearchContractValidationV1.zeroUUID,
              dispositionID != SearchContractValidationV1.zeroUUID,
              SnapshotProjectionValidationV1.validID(packageReleaseID),
              KernelCanonicalHashV1.validSHA256(packageSHA256),
              KernelCanonicalHashV1.validSHA256(workflowSHA256),
              profileRevision > 0, profileRevision <= UInt64(Int.max),
              policyRevision > 0, policyRevision <= UInt64(Int.max),
              dispositionRevision > 0, dispositionRevision <= UInt64(Int.max),
              decisionRevision > 0, decisionRevision <= UInt64(Int.max),
              KernelCanonicalHashV1.validSHA256(profileSHA256),
              KernelCanonicalHashV1.validSHA256(policySHA256),
              KernelCanonicalHashV1.validSHA256(dispositionSHA256),
              KernelCanonicalHashV1.validSHA256(decisionSHA256),
              reasons == reasons.sorted(by: { $0.rawValue < $1.rawValue }),
              !reasons.isEmpty,
              Set(reasons).count == reasons.count,
              immutableHistoric,
              readAllowed == (admission == .readWrite || admission == .readOnly),
              writeAllowed == (admission == .readWrite
                               && Self.writeOperations.contains(operation)),
              operationAllowed == (
                  Self.readOperations.contains(operation)
                      ? readAllowed
                      : Self.writeOperations.contains(operation) && writeAllowed
              ),
              historicArtifact == (lifecycleState == .withdrawn),
              historicExportAllowed == (historicArtifact
                                         && readAllowed
                                         && operation == .export),
              projectionSHA256 == expectedDigest else {
            throw ClientCapabilityReportProjectionFailureV1.invalidValue
        }
    }

    static let writeOperations: Set<PackageLifecycleOperationV1> = [
        .start, .resume, .finalize, .amend, .upgradeDraft,
    ]
    static let readOperations: Set<PackageLifecycleOperationV1> = [
        .view, .export, .restore, .replay,
    ]

    static func digest(
        workspaceID: WorkspaceID,
        decisionID: UUID,
        profileID: UUID,
        policyID: UUID,
        dispositionID: UUID,
        packageReleaseID: String,
        packageSHA256: String,
        workflowSHA256: String,
        profileRevision: UInt64,
        policyRevision: UInt64,
        dispositionRevision: UInt64,
        decisionRevision: UInt64,
        profileSHA256: String,
        policySHA256: String,
        dispositionSHA256: String,
        decisionSHA256: String,
        operation: PackageLifecycleOperationV1,
        admission: ClientAdmissionV1,
        lifecycleState: PackageLifecycleStateV1,
        reasons: [ClientCapabilityReasonV1],
        readAllowed: Bool,
        writeAllowed: Bool,
        operationAllowed: Bool,
        historicArtifact: Bool,
        historicExportAllowed: Bool,
        immutableHistoric: Bool
    ) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            projectionVersion: Self.projectionVersion,
            workspaceID: workspaceID,
            decisionID: decisionID,
            profileID: profileID,
            policyID: policyID,
            dispositionID: dispositionID,
            packageReleaseID: packageReleaseID,
            packageSHA256: packageSHA256,
            workflowSHA256: workflowSHA256,
            profileRevision: profileRevision,
            policyRevision: policyRevision,
            dispositionRevision: dispositionRevision,
            decisionRevision: decisionRevision,
            profileSHA256: profileSHA256,
            policySHA256: policySHA256,
            dispositionSHA256: dispositionSHA256,
            decisionSHA256: decisionSHA256,
            operation: operation,
            admission: admission,
            lifecycleState: lifecycleState,
            reasons: reasons,
            readAllowed: readAllowed,
            writeAllowed: writeAllowed,
            operationAllowed: operationAllowed,
            historicArtifact: historicArtifact,
            historicExportAllowed: historicExportAllowed,
            immutableHistoric: immutableHistoric
        ))
    }

    private var expectedDigest: String {
        // swiftlint:disable:next force_try
        try! Self.digest(
            workspaceID: workspaceID,
            decisionID: decisionID,
            profileID: profileID,
            policyID: policyID,
            dispositionID: dispositionID,
            packageReleaseID: packageReleaseID,
            packageSHA256: packageSHA256,
            workflowSHA256: workflowSHA256,
            profileRevision: profileRevision,
            policyRevision: policyRevision,
            dispositionRevision: dispositionRevision,
            decisionRevision: decisionRevision,
            profileSHA256: profileSHA256,
            policySHA256: policySHA256,
            dispositionSHA256: dispositionSHA256,
            decisionSHA256: decisionSHA256,
            operation: operation,
            admission: admission,
            lifecycleState: lifecycleState,
            reasons: reasons,
            readAllowed: readAllowed,
            writeAllowed: writeAllowed,
            operationAllowed: operationAllowed,
            historicArtifact: historicArtifact,
            historicExportAllowed: historicExportAllowed,
            immutableHistoric: immutableHistoric
        )
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let projectionVersion: String
        let workspaceID: WorkspaceID
        let decisionID: UUID
        let profileID: UUID
        let policyID: UUID
        let dispositionID: UUID
        let packageReleaseID: String
        let packageSHA256: String
        let workflowSHA256: String
        let profileRevision: UInt64
        let policyRevision: UInt64
        let dispositionRevision: UInt64
        let decisionRevision: UInt64
        let profileSHA256: String
        let policySHA256: String
        let dispositionSHA256: String
        let decisionSHA256: String
        let operation: PackageLifecycleOperationV1
        let admission: ClientAdmissionV1
        let lifecycleState: PackageLifecycleStateV1
        let reasons: [ClientCapabilityReasonV1]
        let readAllowed: Bool
        let writeAllowed: Bool
        let operationAllowed: Bool
        let historicArtifact: Bool
        let historicExportAllowed: Bool
        let immutableHistoric: Bool
    }
}

enum ClientCapabilityReportProjectionPolicyV1 {
    static let sectionID = "client-capability-admission"
    static let sectionVersion = 1
    static let projectionVersion = ClientCapabilityReportProjectionV1.projectionVersion
    static let privacyClass = ReportPrivacyClassV1.audienceSafe
    static let metadataOnly = true
    static let requiresCanonicalDecisionBinding = true
    static let allowsHistoricExportAfterWithdrawal = true
    static let withdrawalBlocksNewWork = true
    static let denyWriteUnlessReadWrite = true
    static let denyMigrationQuarantineRejectOperations = true
    static let immutableHistoricDisplay = true
    static let correctionsAreAmendOnly = true
    static let excludesDeviceIdentity = true
    static let excludesUserIdentity = true
    static let excludesEndpointProviderAccount = true
    static let excludesRemoteDeliveryAcknowledgement = true
    static let excludesOriginalPayload = true
    static let excludesUnsupportedClaims = true
    static let supportedFormats: [ReportProjectionFormatV1] = [
        .openJSON, .pdf, .structuredText, .media,
    ]

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }

    static func validate(
        _ projection: ClientCapabilityReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws -> ClientCapabilityReportProjectionV1 {
        guard supports(format) else {
            throw ClientCapabilityReportProjectionFailureV1.invalidValue
        }
        try projection.validate()
        return projection
    }
}

typealias ClientCapabilityAdmissionReportProjectionV1 = ClientCapabilityReportProjectionV1

// MARK: - C23 version-bound field-reference projection

enum FieldReferenceReportProjectionFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidDigest
    case wrongWorkspace
    case staleBinding
    case missingBytes
    case restrictedContent
    case unsupportedFormat
    case identityLeak
}

/// Audience-safe report metadata for one immutable field-reference release
/// bound to a work packet or round session.  The projection carries bounded
/// provenance and lifecycle/readiness facts only; reference bytes, locators,
/// content IDs, license notices, and subject IDs remain outside report data.
struct FieldReferenceReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let projectionVersion = "field-reference-report-v1"

    let schemaVersion: Int
    let projectionVersion: String
    let releaseID: UUID
    let bindingID: UUID
    let referencePackID: String
    let kind: FieldReferenceKindV1
    let semanticVersion: String
    let provenanceKind: FieldReferenceProvenanceKindV1
    let sourceName: String
    let sourceReleaseIdentifier: String
    let licenseScope: FieldReferenceLicenseScopeV1
    let releaseDisposition: FieldReferenceReleaseDispositionV1
    let subjectKind: FieldReferenceSubjectKindV1
    let subjectState: FieldReferenceSubjectStateV1
    let availability: FieldReferenceAvailabilityV1
    let requiredContentCount: Int
    let missingContentCount: Int
    let releaseSHA256: String
    let manifestSHA256: String
    let readinessSHA256: String
    let historicBindingImmutable: Bool
    let restrictedContentOmitted: Bool
    let projectionSHA256: String

    init(
        release: FieldReferenceReleaseV1,
        binding: FieldReferenceBindingV1,
        readiness: FieldReferenceOfflineReadinessV1
    ) throws {
        try release.validate()
        try binding.validate(release: release)
        let canonicalBindingProjection = try WorkSessionFieldReferenceProjectionV1(
            binding: binding,
            release: release,
            readiness: readiness
        )
        try canonicalBindingProjection.validate()
        guard readiness.releaseID == release.releaseID,
              readiness.bindingID == binding.bindingID,
              readiness.missingContentIDs == readiness.missingContentIDs.sorted(),
              Set(readiness.missingContentIDs).count == readiness.missingContentIDs.count,
              KernelCanonicalHashV1.validSHA256(readiness.readinessSHA256) else {
            throw FieldReferenceReportProjectionFailureV1.staleBinding
        }
        if readiness.availability == .readyOffline {
            guard readiness.missingContentIDs.isEmpty else {
                throw FieldReferenceReportProjectionFailureV1.missingBytes
            }
        }
        if readiness.availability == .missingBytes {
            guard !readiness.missingContentIDs.isEmpty else {
                throw FieldReferenceReportProjectionFailureV1.missingBytes
            }
        }
        guard readiness.availability != .revoked
                || release.releaseDisposition == .revoked,
              readiness.availability != .readyOffline
                || release.releaseDisposition == .active else {
            throw FieldReferenceReportProjectionFailureV1.invalidValue
        }

        schemaVersion = Self.schemaVersion
        projectionVersion = Self.projectionVersion
        releaseID = release.releaseID
        bindingID = binding.bindingID
        referencePackID = release.referencePackID
        kind = release.kind
        semanticVersion = release.semanticVersion
        provenanceKind = release.provenance.kind
        sourceName = release.provenance.sourceName
        sourceReleaseIdentifier = release.provenance.sourceReleaseIdentifier
        licenseScope = release.provenance.licenseScope
        releaseDisposition = release.releaseDisposition
        subjectKind = binding.subjectKind
        subjectState = binding.subjectState
        availability = readiness.availability
        requiredContentCount = release.manifest.entries.filter(\.requiredForOpen).count
        missingContentCount = readiness.missingContentIDs.count
        releaseSHA256 = release.releaseSHA256
        manifestSHA256 = release.manifestSHA256
        readinessSHA256 = readiness.readinessSHA256
        historicBindingImmutable = true
        restrictedContentOmitted = true
        projectionSHA256 = try Self.digest(
            releaseID: releaseID,
            bindingID: bindingID,
            referencePackID: referencePackID,
            kind: kind,
            semanticVersion: semanticVersion,
            provenanceKind: provenanceKind,
            sourceName: sourceName,
            sourceReleaseIdentifier: sourceReleaseIdentifier,
            licenseScope: licenseScope,
            releaseDisposition: releaseDisposition,
            subjectKind: subjectKind,
            subjectState: subjectState,
            availability: availability,
            requiredContentCount: requiredContentCount,
            missingContentCount: missingContentCount,
            releaseSHA256: releaseSHA256,
            manifestSHA256: manifestSHA256,
            readinessSHA256: readinessSHA256,
            historicBindingImmutable: historicBindingImmutable,
            restrictedContentOmitted: restrictedContentOmitted
        )
        try validate()
    }

    var isReadyOffline: Bool { availability == .readyOffline && missingContentCount == 0 }
    var isHistoricBinding: Bool { subjectState == .finalized || availability != .readyOffline }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              projectionVersion == Self.projectionVersion,
              releaseID != FieldReferenceValidationV1.zero,
              bindingID != FieldReferenceValidationV1.zero,
              ContentContractValidationV1.validID(referencePackID),
              ContentContractValidationV1.validID(semanticVersion),
              !sourceName.isEmpty,
              !sourceReleaseIdentifier.isEmpty,
              !FieldReferenceLocalizationPolicyV1.containsProhibitedClaim(
                  in: [referencePackID, semanticVersion, sourceName, sourceReleaseIdentifier]
              ),
              !FieldReferenceLocalizationPolicyV1.containsCustomerOrWorkDataLeakage(
                  in: [referencePackID, semanticVersion, sourceName, sourceReleaseIdentifier]
              ),
              requiredContentCount >= 0,
              missingContentCount >= 0,
              missingContentCount <= requiredContentCount,
              KernelCanonicalHashV1.validSHA256(releaseSHA256),
              KernelCanonicalHashV1.validSHA256(manifestSHA256),
              KernelCanonicalHashV1.validSHA256(readinessSHA256),
              historicBindingImmutable,
              restrictedContentOmitted,
              projectionSHA256 == expectedDigest else {
            throw FieldReferenceReportProjectionFailureV1.invalidValue
        }
        if availability == .readyOffline {
            guard missingContentCount == 0 else {
                throw FieldReferenceReportProjectionFailureV1.missingBytes
            }
        }
        if availability == .missingBytes {
            guard missingContentCount > 0 else {
                throw FieldReferenceReportProjectionFailureV1.missingBytes
            }
        }
        guard availability != .revoked || releaseDisposition == .revoked,
              availability != .readyOffline || releaseDisposition == .active else {
            throw FieldReferenceReportProjectionFailureV1.invalidValue
        }
    }

    static func digest(
        releaseID: UUID,
        bindingID: UUID,
        referencePackID: String,
        kind: FieldReferenceKindV1,
        semanticVersion: String,
        provenanceKind: FieldReferenceProvenanceKindV1,
        sourceName: String,
        sourceReleaseIdentifier: String,
        licenseScope: FieldReferenceLicenseScopeV1,
        releaseDisposition: FieldReferenceReleaseDispositionV1,
        subjectKind: FieldReferenceSubjectKindV1,
        subjectState: FieldReferenceSubjectStateV1,
        availability: FieldReferenceAvailabilityV1,
        requiredContentCount: Int,
        missingContentCount: Int,
        releaseSHA256: String,
        manifestSHA256: String,
        readinessSHA256: String,
        historicBindingImmutable: Bool,
        restrictedContentOmitted: Bool
    ) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            projectionVersion: Self.projectionVersion,
            releaseID: releaseID,
            bindingID: bindingID,
            referencePackID: referencePackID,
            kind: kind,
            semanticVersion: semanticVersion,
            provenanceKind: provenanceKind,
            sourceName: sourceName,
            sourceReleaseIdentifier: sourceReleaseIdentifier,
            licenseScope: licenseScope,
            releaseDisposition: releaseDisposition,
            subjectKind: subjectKind,
            subjectState: subjectState,
            availability: availability,
            requiredContentCount: requiredContentCount,
            missingContentCount: missingContentCount,
            releaseSHA256: releaseSHA256,
            manifestSHA256: manifestSHA256,
            readinessSHA256: readinessSHA256,
            historicBindingImmutable: historicBindingImmutable,
            restrictedContentOmitted: restrictedContentOmitted
        ))
    }

    private var expectedDigest: String {
        // swiftlint:disable:next force_try
        try! Self.digest(
            releaseID: releaseID,
            bindingID: bindingID,
            referencePackID: referencePackID,
            kind: kind,
            semanticVersion: semanticVersion,
            provenanceKind: provenanceKind,
            sourceName: sourceName,
            sourceReleaseIdentifier: sourceReleaseIdentifier,
            licenseScope: licenseScope,
            releaseDisposition: releaseDisposition,
            subjectKind: subjectKind,
            subjectState: subjectState,
            availability: availability,
            requiredContentCount: requiredContentCount,
            missingContentCount: missingContentCount,
            releaseSHA256: releaseSHA256,
            manifestSHA256: manifestSHA256,
            readinessSHA256: readinessSHA256,
            historicBindingImmutable: historicBindingImmutable,
            restrictedContentOmitted: restrictedContentOmitted
        )
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let projectionVersion: String
        let releaseID: UUID
        let bindingID: UUID
        let referencePackID: String
        let kind: FieldReferenceKindV1
        let semanticVersion: String
        let provenanceKind: FieldReferenceProvenanceKindV1
        let sourceName: String
        let sourceReleaseIdentifier: String
        let licenseScope: FieldReferenceLicenseScopeV1
        let releaseDisposition: FieldReferenceReleaseDispositionV1
        let subjectKind: FieldReferenceSubjectKindV1
        let subjectState: FieldReferenceSubjectStateV1
        let availability: FieldReferenceAvailabilityV1
        let requiredContentCount: Int
        let missingContentCount: Int
        let releaseSHA256: String
        let manifestSHA256: String
        let readinessSHA256: String
        let historicBindingImmutable: Bool
        let restrictedContentOmitted: Bool
    }
}

enum FieldReferenceReportProjectionPolicyV1 {
    static let sectionID = "field-reference"
    static let projectionVersion = FieldReferenceReportProjectionV1.projectionVersion
    static let metadataOnly = true
    static let excludesReferenceBytes = true
    static let excludesPrivateLocators = true
    static let excludesLicenseSecrets = true
    static let excludesSubjectIdentity = true
    static let excludesObservationClaims = true
    static let excludesComplianceClaims = true
    static let silentReleaseReplacementAllowed = false
    static let supportedFormats: Set<ReportProjectionFormatV1> = [
        .openJSON, .pdf, .structuredText,
    ]

    static func validate(
        _ projection: FieldReferenceReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws -> FieldReferenceReportProjectionV1 {
        guard supportedFormats.contains(format) else {
            throw FieldReferenceReportProjectionFailureV1.unsupportedFormat
        }
        try projection.validate()
        guard metadataOnly,
              excludesReferenceBytes,
              excludesPrivateLocators,
              excludesLicenseSecrets,
              excludesSubjectIdentity,
              excludesObservationClaims,
              excludesComplianceClaims,
              !silentReleaseReplacementAllowed else {
            throw FieldReferenceReportProjectionFailureV1.identityLeak
        }
        return projection
    }
}

// MARK: - C25 bounded survey-definition report consumer

enum SurveyDefinitionConsumerFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case privacyViolation
    case unsupportedFormat
    case duplicateIdentity
    case staleBinding
    case limitExceeded
}

enum SurveyDefinitionConsumerPolicyV1 {
    static let schemaVersion = 1
    static let sourceKind = "SURVEY_DEFINITION_RELEASE"
    static let projectionVersion = "SURVEY_REPORT_PROJECTION_V1"
    static let metadataOnly = true
    static let derivedOnly = true
    static let historicDisplayFrozen = true
    static let includesAnswers = false
    static let includesPromptText = false
    static let includesActorIdentity = false
    static let includesPrivateLocators = false
    static let includesEvidenceBytes = false
    static let allowsInspectionPassFailClaim = false
    static let allowsCertificationClaim = false
    static let allowsComplianceClaim = false
    static let allowsTrainingClaim = false
    static let allowedFormats: Set<ReportProjectionFormatV1> = [.openJSON, .pdf, .structuredText]

    static func validID(_ value: String) -> Bool {
        SurveyDefinitionLimitsV1.token(value, maximumBytes: 160)
    }

    static func validDigest(_ value: String) -> Bool {
        KernelCanonicalHashV1.validSHA256(value)
    }

    static func containsUnsupportedClaim(_ values: [String]) -> Bool {
        let prohibited = [
            "inspection pass", "inspection fail", "inspection passed", "inspection failed",
            "certified", "certification", "compliant", "compliance", "training complete",
            "authorized", "approved", "safe", "warranty", "recall",
        ]
        return values.map { $0.lowercased() }.contains { value in
            prohibited.contains { value.contains($0) }
        }
    }
}

struct SurveyDefinitionBoundedMetadataV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let definitionID: String
    let releaseID: String
    let activityKind: ActivityKindV1
    let lifecycleState: SurveyDefinitionLifecycleStateV1
    let releaseRevision: UInt64
    let releaseSHA256: String
    let localizationReleaseSHA256: String
    let sectionCount: Int
    let factCount: Int
    let reportProjectionID: String
    let claimsProfileID: String

    init(
        release: SurveyDefinitionReleaseV1,
        lifecycleState: SurveyDefinitionLifecycleStateV1
    ) throws {
        try release.validate()
        schemaVersion = Self.schemaVersion
        definitionID = release.definitionID.uuidString.lowercased()
        releaseID = release.releaseID.uuidString.lowercased()
        activityKind = release.activityKind
        self.lifecycleState = lifecycleState
        releaseRevision = release.revision
        releaseSHA256 = release.releaseSHA256
        localizationReleaseSHA256 = release.localizationReleaseSHA256
        sectionCount = release.sections.count
        factCount = release.sections.flatMap(\.facts).count
        reportProjectionID = release.reportProjection.projectionID
        claimsProfileID = release.claimsProfile.profileID
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              SurveyDefinitionConsumerPolicyV1.validID(definitionID),
              SurveyDefinitionConsumerPolicyV1.validID(releaseID),
              SurveyDefinitionConsumerPolicyV1.validDigest(releaseSHA256),
              SurveyDefinitionConsumerPolicyV1.validDigest(localizationReleaseSHA256),
              SurveyDefinitionConsumerPolicyV1.validID(reportProjectionID),
              SurveyDefinitionConsumerPolicyV1.validID(claimsProfileID),
              releaseRevision > 0,
              (0...SurveyDefinitionLimitsV1.maximumSections).contains(sectionCount),
              (0...SurveyDefinitionLimitsV1.maximumFacts).contains(factCount) else {
            throw SurveyDefinitionConsumerFailureV1.invalidValue
        }
    }
}

struct SurveyDefinitionReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let metadata: SurveyDefinitionBoundedMetadataV1
    let projectionVersion: String
    let headingLocalizationKey: String
    let emptyValueLocalizationKey: String
    let nextStepLocalizationKey: String
    let sectionIDs: [String]
    let includedFactIDs: [String]
    let historicDisplayFrozen: Bool
    let includesAnswers: Bool
    let includesPromptText: Bool
    let includesActorIdentity: Bool
    let includesPrivateLocators: Bool
    let includesEvidenceBytes: Bool

    init(
        release: SurveyDefinitionReleaseV1,
        lifecycleState: SurveyDefinitionLifecycleStateV1
    ) throws {
        let bounded = try SurveyDefinitionBoundedMetadataV1(
            release: release,
            lifecycleState: lifecycleState
        )
        schemaVersion = Self.schemaVersion
        metadata = bounded
        projectionVersion = SurveyDefinitionConsumerPolicyV1.projectionVersion
        headingLocalizationKey = "survey.definition.report.heading"
        emptyValueLocalizationKey = "survey.definition.value.not_observed"
        nextStepLocalizationKey = "survey.definition.next_step.review_recorded_facts"
        sectionIDs = release.reportProjection.sectionIDs.sorted()
        includedFactIDs = release.reportProjection.includedFactIDs.sorted()
        historicDisplayFrozen = SurveyDefinitionConsumerPolicyV1.historicDisplayFrozen
        includesAnswers = SurveyDefinitionConsumerPolicyV1.includesAnswers
        includesPromptText = SurveyDefinitionConsumerPolicyV1.includesPromptText
        includesActorIdentity = SurveyDefinitionConsumerPolicyV1.includesActorIdentity
        includesPrivateLocators = SurveyDefinitionConsumerPolicyV1.includesPrivateLocators
        includesEvidenceBytes = SurveyDefinitionConsumerPolicyV1.includesEvidenceBytes
        try validate()
    }

    func validate(format: ReportProjectionFormatV1? = nil) throws {
        if let format, !SurveyDefinitionConsumerPolicyV1.allowedFormats.contains(format) {
            throw SurveyDefinitionConsumerFailureV1.unsupportedFormat
        }
        try metadata.validate()
        guard schemaVersion == Self.schemaVersion,
              projectionVersion == SurveyDefinitionConsumerPolicyV1.projectionVersion,
              [headingLocalizationKey, emptyValueLocalizationKey, nextStepLocalizationKey]
                .allSatisfy(SurveyDefinitionConsumerPolicyV1.validID),
              sectionIDs == sectionIDs.sorted(),
              includedFactIDs == includedFactIDs.sorted(),
              Set(sectionIDs).count == sectionIDs.count,
              Set(includedFactIDs).count == includedFactIDs.count,
              sectionIDs.count <= SurveyDefinitionLimitsV1.maximumSections,
              includedFactIDs.count <= SurveyDefinitionLimitsV1.maximumFacts,
              historicDisplayFrozen,
              !includesAnswers,
              !includesPromptText,
              !includesActorIdentity,
              !includesPrivateLocators,
              !includesEvidenceBytes,
              SurveyDefinitionConsumerPolicyV1.metadataOnly,
              SurveyDefinitionConsumerPolicyV1.derivedOnly else {
            throw SurveyDefinitionConsumerFailureV1.privacyViolation
        }
        guard !SurveyDefinitionConsumerPolicyV1.containsUnsupportedClaim([
            headingLocalizationKey, emptyValueLocalizationKey, nextStepLocalizationKey
        ]) else {
            throw SurveyDefinitionConsumerFailureV1.privacyViolation
        }
    }
}

// MARK: - C27 bounded asset-locator report projection

enum AssetLocatorReportProjectionFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case privacyViolation
    case unsupportedFormat
    case staleBinding
    case limitExceeded
}

enum AssetLocatorReportProjectionPolicyV1 {
    static let sectionID = "asset.locator"
    static let projectionVersion = "ASSET_LOCATOR_REPORT_PROJECTION_V1"
    static let supportedFormats: [ReportProjectionFormatV1] = [.openJSON]
    static let metadataOnly = true
    static let derivedOnly = true
    static let historicDisplayFrozen = true
    static let excludesOpaqueInput = true
    static let excludesPrivateKeyMaterial = true
    static let excludesSecrets = true
    static let excludesVendorIdentifiers = true
    static let excludesActorIdentity = true
    static let excludesPermissionClaims = true
    static let excludesNetworkResolutionClaims = true
    static let excludesUnsupportedClaims = true

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }

    static func containsUnsupportedClaim(_ values: [String]) -> Bool {
        AssetLocatorLocalizationPolicyV1.containsProhibitedClaim(values)
    }

    static func validate() throws {
        guard supportedFormats == [.openJSON], metadataOnly, derivedOnly,
              historicDisplayFrozen, excludesOpaqueInput,
              excludesPrivateKeyMaterial, excludesSecrets,
              excludesVendorIdentifiers, excludesActorIdentity,
              excludesPermissionClaims, excludesNetworkResolutionClaims,
              excludesUnsupportedClaims else {
            throw AssetLocatorReportProjectionFailureV1.invalidValue
        }
    }
}

enum AssetLocatorReportProjectionValidationV1 {
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static let selectedOutcomes: Set<LocatorResolutionOutcomeV1> = [
        .matched, .retired, .revoked, .replaced,
    ]

    static func validWorkspace(_ value: WorkspaceID) -> Bool {
        value.rawValue != zeroUUID
    }
}

/// Metadata that may be copied into a report.  The representation is a
/// closed kind rather than the external key or signed payload itself.
struct AssetLocatorBoundedMetadataV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let locatorID: UUID
    let assetID: UUID
    let representation: String
    let state: AssetLocatorStateV1
    let replacedByLocatorID: UUID?
    let revision: UInt64
    let locatorSHA256: String
    let historicDisplayFrozen: Bool
    let includesOpaqueInput: Bool
    let includesPrivateKeyMaterial: Bool
    let includesSecrets: Bool
    let includesVendorIdentifiers: Bool
    let includesActorIdentity: Bool

    init(locator: AssetLocatorV1) throws {
        try locator.validate()
        schemaVersion = Self.schemaVersion
        workspaceID = locator.workspaceID
        locatorID = locator.locatorID
        assetID = locator.assetID
        switch locator.representation {
        case .localSigned: representation = "LOCAL_SIGNED"
        case .externalKey: representation = "EXTERNAL_KEY"
        }
        state = locator.state
        replacedByLocatorID = locator.replacedByLocatorID
        revision = locator.revision
        locatorSHA256 = locator.locatorSHA256
        historicDisplayFrozen = true
        includesOpaqueInput = false
        includesPrivateKeyMaterial = false
        includesSecrets = false
        includesVendorIdentifiers = false
        includesActorIdentity = false
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              AssetLocatorReportProjectionValidationV1.validWorkspace(workspaceID),
              locatorID != AssetLocatorReportProjectionValidationV1.zeroUUID,
              assetID != AssetLocatorReportProjectionValidationV1.zeroUUID,
              ["LOCAL_SIGNED", "EXTERNAL_KEY"].contains(representation),
              revision > 0,
              KernelCanonicalHashV1.validSHA256(locatorSHA256),
              (state == .replaced) == (replacedByLocatorID != nil),
              replacedByLocatorID != locatorID,
              historicDisplayFrozen,
              !includesOpaqueInput, !includesPrivateKeyMaterial,
              !includesSecrets, !includesVendorIdentifiers,
              !includesActorIdentity else {
            throw AssetLocatorReportProjectionFailureV1.privacyViolation
        }
    }
}

struct AssetLocatorResolutionReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let source: LocatorInputSourceV1
    let inputSHA256: String
    let outcome: LocatorResolutionOutcomeV1
    let matchedLocator: AssetLocatorReferenceV1?
    let matchedAssetID: UUID?
    let replacementLocatorID: UUID?
    let candidateCount: Int
    let evaluatedAt: Date
    let resolutionSHA256: String
    let historicDisplayFrozen: Bool

    init(resolution: LocatorResolutionV1) throws {
        try resolution.validate()
        schemaVersion = Self.schemaVersion
        workspaceID = resolution.workspaceID
        source = resolution.source
        inputSHA256 = resolution.inputSHA256
        outcome = resolution.outcome
        matchedLocator = resolution.matchedLocator
        matchedAssetID = resolution.matchedAssetID
        replacementLocatorID = resolution.replacementLocatorID
        candidateCount = resolution.candidateLocators.count
        evaluatedAt = resolution.evaluatedAt
        resolutionSHA256 = resolution.resolutionSHA256
        historicDisplayFrozen = true
        try validate()
    }

    func validate() throws {
        try matchedLocator?.validate()
        guard schemaVersion == Self.schemaVersion,
              AssetLocatorReportProjectionValidationV1.validWorkspace(workspaceID),
              KernelCanonicalHashV1.validSHA256(inputSHA256),
              KernelCanonicalHashV1.validSHA256(resolutionSHA256),
              matchedAssetID.map({ $0 != AssetLocatorReportProjectionValidationV1.zeroUUID }) ?? true,
              replacementLocatorID.map({ $0 != AssetLocatorReportProjectionValidationV1.zeroUUID }) ?? true,
              evaluatedAt.timeIntervalSinceReferenceDate.isFinite,
              (0...AssetLocatorLimitsV1.maximumCandidates).contains(candidateCount),
              historicDisplayFrozen else {
            throw AssetLocatorReportProjectionFailureV1.invalidValue
        }
        let selected = matchedLocator != nil && matchedAssetID != nil
        guard AssetLocatorReportProjectionValidationV1.selectedOutcomes.contains(outcome)
            ? selected : !selected else {
            throw AssetLocatorReportProjectionFailureV1.invalidValue
        }
        if outcome == .replaced {
            guard replacementLocatorID != nil else {
                throw AssetLocatorReportProjectionFailureV1.invalidValue
            }
        } else {
            guard replacementLocatorID == nil else {
                throw AssetLocatorReportProjectionFailureV1.invalidValue
            }
        }
    }
}

/// The report projection contains only the already-recorded result.  It does
/// not resolve a current locator, rewrite a finalized report, or retain the
/// input bytes used by a resolver.
struct AssetLocatorReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let projectionVersion: String
    let metadata: AssetLocatorBoundedMetadataV1?
    let resolution: AssetLocatorResolutionReportProjectionV1
    let frozenInterpretation: FrozenAssetLocatorInterpretationV1?
    let historicDisplayFrozen: Bool
    let includesOpaqueInput: Bool
    let includesPrivateKeyMaterial: Bool
    let includesSecrets: Bool
    let includesVendorIdentifiers: Bool
    let includesActorIdentity: Bool

    init(
        resolution: LocatorResolutionV1,
        locator: AssetLocatorV1? = nil,
        frozenInterpretation: FrozenAssetLocatorInterpretationV1? = nil
    ) throws {
        try resolution.validate()
        if let locator {
            try locator.validate()
            guard locator.workspaceID == resolution.workspaceID,
                  resolution.matchedLocator.map({ $0.locatorID == locator.locatorID }) ?? true else {
                throw AssetLocatorReportProjectionFailureV1.invalidValue
            }
            metadata = try AssetLocatorBoundedMetadataV1(locator: locator)
        } else {
            metadata = nil
        }
        self.resolution = try AssetLocatorResolutionReportProjectionV1(
            resolution: resolution
        )
        self.frozenInterpretation = frozenInterpretation
        schemaVersion = Self.schemaVersion
        projectionVersion = AssetLocatorReportProjectionPolicyV1.projectionVersion
        historicDisplayFrozen = true
        includesOpaqueInput = false
        includesPrivateKeyMaterial = false
        includesSecrets = false
        includesVendorIdentifiers = false
        includesActorIdentity = false
        try validate()
    }

    init(
        locator: AssetLocatorV1,
        resolution: LocatorResolutionV1? = nil,
        frozenInterpretation: FrozenAssetLocatorInterpretationV1? = nil
    ) throws {
        try locator.validate()
        let resolved: LocatorResolutionV1
        if let resolution {
            resolved = resolution
        } else {
            resolved = try Self.syntheticResolution(for: locator)
        }
        try self.init(
            resolution: resolved,
            locator: locator,
            frozenInterpretation: frozenInterpretation
        )
    }

    func validate(format: ReportProjectionFormatV1? = nil) throws {
        try AssetLocatorReportProjectionPolicyV1.validate()
        if let format, !AssetLocatorReportProjectionPolicyV1.supports(format) {
            throw AssetLocatorReportProjectionFailureV1.unsupportedFormat
        }
        try resolution.validate()
        try metadata?.validate()
        try frozenInterpretation?.validate()
        guard schemaVersion == Self.schemaVersion,
              projectionVersion == AssetLocatorReportProjectionPolicyV1.projectionVersion,
              historicDisplayFrozen,
              !includesOpaqueInput, !includesPrivateKeyMaterial,
              !includesSecrets, !includesVendorIdentifiers,
              !includesActorIdentity else {
            throw AssetLocatorReportProjectionFailureV1.privacyViolation
        }

        let requiresMetadata = AssetLocatorReportProjectionValidationV1
            .selectedOutcomes.contains(resolution.outcome)
        guard (metadata != nil) == requiresMetadata else {
            throw AssetLocatorReportProjectionFailureV1.invalidValue
        }
        if let metadata {
            guard metadata.workspaceID == resolution.workspaceID,
                  resolution.matchedLocator?.locatorID == metadata.locatorID,
                  resolution.matchedLocator?.revision == metadata.revision,
                  resolution.matchedLocator?.locatorSHA256 == metadata.locatorSHA256,
                  resolution.matchedAssetID == metadata.assetID else {
                throw AssetLocatorReportProjectionFailureV1.invalidValue
            }
            if resolution.outcome == .replaced {
                guard resolution.replacementLocatorID == metadata.replacedByLocatorID else {
                    throw AssetLocatorReportProjectionFailureV1.invalidValue
                }
            }
            let expectedOutcome: LocatorResolutionOutcomeV1
            switch metadata.state {
            case .active: expectedOutcome = .matched
            case .retired: expectedOutcome = .retired
            case .revoked: expectedOutcome = .revoked
            case .replaced: expectedOutcome = .replaced
            }
            guard resolution.outcome == expectedOutcome else {
                throw AssetLocatorReportProjectionFailureV1.invalidValue
            }
        }
        if let frozenInterpretation {
            guard resolution.outcome == .matched,
                  let metadata,
                  frozenInterpretation.locator.locatorID == metadata.locatorID,
                  frozenInterpretation.locator.revision == metadata.revision,
                  frozenInterpretation.locator.locatorSHA256 == metadata.locatorSHA256,
                  frozenInterpretation.assetIDAtCapture == metadata.assetID else {
                throw AssetLocatorReportProjectionFailureV1.staleBinding
            }
        }
        guard !AssetLocatorReportProjectionPolicyV1.containsUnsupportedClaim([
            AssetLocatorLocalizationKeyV1.heading.englishDefaultValue,
            AssetLocatorLocalizationKeyV1.claimBoundary.englishDefaultValue,
            AssetLocatorLocalizationKeyV1.nextStep.englishDefaultValue,
        ]) else {
            throw AssetLocatorReportProjectionFailureV1.privacyViolation
        }
    }

    func semanticDigest() throws -> String {
        try validate()
        return KernelCanonicalHashV1.sha256(try AssetLocatorCanonicalCodecV1.encode(self))
    }

    private static func syntheticResolution(
        for locator: AssetLocatorV1
    ) throws -> LocatorResolutionV1 {
        let outcome: LocatorResolutionOutcomeV1
        switch locator.state {
        case .active: outcome = .matched
        case .retired: outcome = .retired
        case .revoked: outcome = .revoked
        case .replaced: outcome = .replaced
        }
        return try LocatorResolutionV1(
            workspaceID: locator.workspaceID,
            source: .manual,
            inputSHA256: locator.locatorSHA256,
            outcome: outcome,
            matchedLocator: try locator.reference,
            matchedAssetID: locator.assetID,
            replacementLocatorID: locator.replacedByLocatorID,
            evaluatedAt: locator.recordedAt
        )
    }
}

// MARK: - C29 versioned plan/rebase report projection

enum PlanReportProjectionFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidDigest
    case wrongWorkspace
    case staleReference
    case stalePreview
    case componentConflict
    case missingReceipt
    case unsupportedFormat
}

/// Bounded placement metadata for reports. Source content and locator
/// bindings remain outside this derivative; coordinates are the canonical
/// normalized values from the plan placement record.
struct PlanPlacementReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let placementID: UUID
    let subjectKind: PlanPlacementSubjectKindV1
    let subjectID: UUID
    let planRevisionID: UUID
    let spatialFrameID: UUID
    let xMillionths: Int64
    let yMillionths: Int64
    let disposition: PlanPlacementDispositionV1
    let revision: UInt64
    let placementSHA256: String

    init(
        placement: PlanPlacementV1,
        expectedRevision: PlanRevisionReferenceV1
    ) throws {
        try placement.validateIntrinsic()
        guard placement.planRevision == expectedRevision else {
            throw PlanReportProjectionFailureV1.staleReference
        }
        schemaVersion = Self.schemaVersion
        placementID = placement.placementID
        subjectKind = placement.subjectKind
        subjectID = placement.subjectID
        planRevisionID = placement.planRevision.planRevisionID
        spatialFrameID = placement.spatialFrameID
        xMillionths = placement.x.millionths
        yMillionths = placement.y.millionths
        disposition = placement.disposition
        revision = placement.revision
        placementSHA256 = placement.placementSHA256
        try validate()
    }

    func validate() throws {
        try PlanLimitsV1.id(placementID)
        try PlanLimitsV1.id(subjectID)
        try PlanLimitsV1.id(planRevisionID)
        try PlanLimitsV1.id(spatialFrameID)
        try PlanLimitsV1.revision(revision)
        try PlanLimitsV1.digest(placementSHA256)
        guard schemaVersion == Self.schemaVersion,
              revision <= UInt64(Int.max),
              (0...PlanLimitsV1.normalizedScale).contains(xMillionths),
              (0...PlanLimitsV1.normalizedScale).contains(yMillionths) else {
            throw PlanReportProjectionFailureV1.invalidValue
        }
    }
}

struct PlanRebasePreviewReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let previewID: UUID
    let oldRevision: PlanRevisionReferenceV1
    let newRevision: PlanRevisionReferenceV1
    let transformSHA256: String
    let registrySHA256: String
    let componentIDs: [String]
    let rowCount: Int
    let acceptedRowCount: Int
    let reviewRequiredRowCount: Int
    let warningCodes: [PlanRebaseWarningCodeV1]
    let requiresReview: Bool
    let expectedRevision: UInt64
    let generatedAt: Date
    let previewSHA256: String

    init(preview: RebasePreviewV1) throws {
        try preview.validate()
        schemaVersion = Self.schemaVersion
        previewID = preview.previewID
        oldRevision = preview.oldRevision
        newRevision = preview.newRevision
        transformSHA256 = preview.transform.transformSHA256
        registrySHA256 = preview.registrySHA256
        componentIDs = preview.contributions.map(\.componentID).sorted()
        rowCount = preview.rows.count
        acceptedRowCount = preview.rows.filter { $0.disposition == .accepted }.count
        reviewRequiredRowCount = preview.rows.filter { $0.disposition != .accepted }.count
        warningCodes = Array(Set(preview.warnings.map(\.code))).sorted {
            $0.rawValue < $1.rawValue
        }
        requiresReview = preview.requiresReview
        expectedRevision = preview.expectedRevision
        generatedAt = preview.generatedAt
        previewSHA256 = preview.previewSHA256
        try validate()
    }

    func validate() throws {
        try PlanLimitsV1.id(previewID)
        try oldRevision.validate()
        try newRevision.validate()
        guard oldRevision.revision <= UInt64(Int.max),
              newRevision.revision <= UInt64(Int.max) else {
            throw PlanReportProjectionFailureV1.invalidValue
        }
        try PlanLimitsV1.digest(transformSHA256)
        try PlanLimitsV1.digest(registrySHA256)
        try componentIDs.forEach(PlanLimitsV1.token)
        try PlanLimitsV1.instant(generatedAt)
        try PlanLimitsV1.digest(previewSHA256)
        guard schemaVersion == Self.schemaVersion,
              componentIDs == componentIDs.sorted(),
              Set(componentIDs).count == componentIDs.count,
              rowCount >= 0,
              acceptedRowCount >= 0,
              reviewRequiredRowCount >= 0,
              acceptedRowCount + reviewRequiredRowCount == rowCount,
              expectedRevision > 0,
              expectedRevision <= UInt64(Int.max),
              warningCodes == warningCodes.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(warningCodes).count == warningCodes.count else {
            throw PlanReportProjectionFailureV1.invalidValue
        }
    }
}

struct PlanRebaseReceiptReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let receiptID: UUID
    let previewID: UUID
    let previewSHA256: String
    let decision: PlanRebaseDecisionV1
    let resultingRevision: PlanRevisionReferenceV1?
    let resultingPlacementsSHA256: String?
    let canonicalMutationReceiptSHA256: String?
    let recordedAt: Date
    let revision: UInt64
    let receiptSHA256: String

    init(receipt: RebaseReceiptV1, preview: RebasePreviewV1) throws {
        try receipt.validate(preview: preview)
        schemaVersion = Self.schemaVersion
        receiptID = receipt.receiptID
        previewID = receipt.previewID
        previewSHA256 = receipt.previewSHA256
        decision = receipt.decision
        resultingRevision = receipt.resultingRevision
        resultingPlacementsSHA256 = receipt.resultingPlacementsSHA256
        canonicalMutationReceiptSHA256 = receipt.canonicalMutationReceiptSHA256
        recordedAt = receipt.recordedAt
        revision = receipt.revision
        receiptSHA256 = receipt.receiptSHA256
        try validate(
            previewID: preview.previewID,
            previewSHA256: preview.previewSHA256
        )
    }

    func validate(
        previewID expectedPreviewID: UUID,
        previewSHA256 expectedPreviewSHA256: String
    ) throws {
        try PlanLimitsV1.id(receiptID)
        try PlanLimitsV1.id(previewID)
        try PlanLimitsV1.digest(previewSHA256)
        try resultingRevision?.validate()
        try resultingPlacementsSHA256.map(PlanLimitsV1.digest)
        try canonicalMutationReceiptSHA256.map(PlanLimitsV1.digest)
        try PlanLimitsV1.instant(recordedAt)
        try PlanLimitsV1.revision(revision)
        try PlanLimitsV1.digest(receiptSHA256)
        let approved = decision == .approved
        guard schemaVersion == Self.schemaVersion,
              previewID == expectedPreviewID,
              previewSHA256 == expectedPreviewSHA256,
              revision <= UInt64(Int.max),
              resultingRevision.map({ $0.revision <= UInt64(Int.max) }) ?? true,
              approved == (resultingRevision != nil
                           && resultingPlacementsSHA256 != nil
                           && canonicalMutationReceiptSHA256 != nil) else {
            throw PlanReportProjectionFailureV1.stalePreview
        }
    }
}

struct PlanReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let projectionVersion = "PLAN_REPORT_PROJECTION_V1"

    let schemaVersion: Int
    let projectionVersion: String
    let workspaceID: UUID
    let documentReference: PlanDocumentReferenceV1
    let revisionReference: PlanRevisionReferenceV1
    let documentState: PlanDocumentStateV1
    let revisionState: PlanRevisionStateV1
    let contentReleaseID: UUID
    let contentReleaseRevision: UInt64
    let contentReleaseSHA256: String
    let contentManifestSHA256: String
    let pageCount: Int
    let placements: [PlanPlacementReportProjectionV1]
    let rebasePreview: PlanRebasePreviewReportProjectionV1?
    let rebaseReceipt: PlanRebaseReceiptReportProjectionV1?
    let historicDisplayIsFrozen: Bool
    let previewIsNotApplied: Bool
    let projectionSHA256: String

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let projectionVersion: String
        let workspaceID: UUID
        let documentReference: PlanDocumentReferenceV1
        let revisionReference: PlanRevisionReferenceV1
        let documentState: PlanDocumentStateV1
        let revisionState: PlanRevisionStateV1
        let contentReleaseID: UUID
        let contentReleaseRevision: UInt64
        let contentReleaseSHA256: String
        let contentManifestSHA256: String
        let pageCount: Int
        let placements: [PlanPlacementReportProjectionV1]
        let rebasePreview: PlanRebasePreviewReportProjectionV1?
        let rebaseReceipt: PlanRebaseReceiptReportProjectionV1?
        let historicDisplayIsFrozen: Bool
        let previewIsNotApplied: Bool
    }

    init(
        document: PlanDocumentV1,
        revision: PlanRevisionV1,
        placements: [PlanPlacementV1],
        preview: RebasePreviewV1? = nil,
        receipt: RebaseReceiptV1? = nil
    ) throws {
        try document.validateIntrinsic()
        try revision.validateIntrinsic()
        let documentReference = try document.reference
        let revisionReference = try revision.reference
        guard revision.workspaceID == document.workspaceID,
              revision.planDocument.planDocumentID == document.planDocumentID,
              revision.planDocument == documentReference,
              placements.count <= PlanLimitsV1.maximumPlacements,
              placements.allSatisfy({ placement in
                  placement.workspaceID == revision.workspaceID
                      && placement.planRevision == revisionReference
                      && revision.spatialFrames.contains(where: {
                          $0.frameID == placement.spatialFrameID
                      })
              }) else {
            throw PlanReportProjectionFailureV1.wrongWorkspace
        }
        let projectedPlacements = try placements
            .sorted { $0.placementID.uuidString < $1.placementID.uuidString }
            .map {
                try PlanPlacementReportProjectionV1(
                    placement: $0,
                    expectedRevision: revisionReference
                )
            }
        guard Set(projectedPlacements.map(\.placementID)).count == projectedPlacements.count else {
            throw PlanReportProjectionFailureV1.invalidValue
        }

        let projectedPreview = try preview.map {
            try PlanRebasePreviewReportProjectionV1(preview: $0)
        }
        if let preview {
            guard preview.workspaceID == revision.workspaceID,
                  preview.newRevision == revisionReference else {
                throw PlanReportProjectionFailureV1.stalePreview
            }
        }
        let projectedReceipt: PlanRebaseReceiptReportProjectionV1?
        if let receipt {
            guard let preview else {
                throw PlanReportProjectionFailureV1.missingReceipt
            }
            projectedReceipt = try PlanRebaseReceiptReportProjectionV1(
                receipt: receipt,
                preview: preview
            )
        } else {
            projectedReceipt = nil
        }

        schemaVersion = Self.schemaVersion
        projectionVersion = Self.projectionVersion
        workspaceID = revision.workspaceID.rawValue
        self.documentReference = documentReference
        self.revisionReference = revisionReference
        documentState = document.state
        revisionState = revision.state
        contentReleaseID = revision.contentBinding.fieldReferenceReleaseID
        contentReleaseRevision = revision.contentBinding.fieldReferenceReleaseRevision
        contentReleaseSHA256 = revision.contentBinding.fieldReferenceReleaseSHA256
        contentManifestSHA256 = revision.contentBinding.fieldReferenceManifestSHA256
        pageCount = revision.pages.count
        self.placements = projectedPlacements
        rebasePreview = projectedPreview
        rebaseReceipt = projectedReceipt
        historicDisplayIsFrozen = true
        previewIsNotApplied = true
        projectionSHA256 = try PlanCanonicalCodecV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                projectionVersion: Self.projectionVersion,
                workspaceID: workspaceID,
                documentReference: documentReference,
                revisionReference: revisionReference,
                documentState: documentState,
                revisionState: revisionState,
                contentReleaseID: contentReleaseID,
                contentReleaseRevision: contentReleaseRevision,
                contentReleaseSHA256: contentReleaseSHA256,
                contentManifestSHA256: contentManifestSHA256,
                pageCount: pageCount,
                placements: projectedPlacements,
                rebasePreview: projectedPreview,
                rebaseReceipt: projectedReceipt,
                historicDisplayIsFrozen: true,
                previewIsNotApplied: true
            )
        )
        try validate()
    }

    func validate() throws {
        try PlanLimitsV1.id(workspaceID)
        try documentReference.validate()
        try revisionReference.validate()
        try PlanLimitsV1.id(contentReleaseID)
        try PlanLimitsV1.revision(contentReleaseRevision)
        try PlanLimitsV1.digest(contentReleaseSHA256)
        try PlanLimitsV1.digest(contentManifestSHA256)
        try placements.forEach { try $0.validate() }
        guard placements.allSatisfy({
            $0.planRevisionID == revisionReference.planRevisionID
        }) else {
            throw PlanReportProjectionFailureV1.staleReference
        }
        if let preview = rebasePreview {
            try preview.validate()
            guard preview.newRevision == revisionReference else {
                throw PlanReportProjectionFailureV1.stalePreview
            }
            if let receipt = rebaseReceipt {
                try receipt.validate(
                    previewID: preview.previewID,
                    previewSHA256: preview.previewSHA256
                )
            }
        } else if rebaseReceipt != nil {
            throw PlanReportProjectionFailureV1.missingReceipt
        }
        guard schemaVersion == Self.schemaVersion,
              projectionVersion == Self.projectionVersion,
              documentReference.planDocumentID == revisionReference.planDocumentID,
              documentReference.revision <= UInt64(Int.max),
              revisionReference.revision <= UInt64(Int.max),
              contentReleaseRevision <= UInt64(Int.max),
              pageCount > 0,
              pageCount <= PlanLimitsV1.maximumPages,
              placements == placements.sorted(by: {
                  $0.placementID.uuidString < $1.placementID.uuidString
              }),
              Set(placements.map(\.placementID)).count == placements.count,
              historicDisplayIsFrozen,
              previewIsNotApplied,
              projectionSHA256 == (try PlanCanonicalCodecV1.sha256(
                  DigestBasis(
                      schemaVersion: schemaVersion,
                      projectionVersion: projectionVersion,
                      workspaceID: workspaceID,
                      documentReference: documentReference,
                      revisionReference: revisionReference,
                      documentState: documentState,
                      revisionState: revisionState,
                      contentReleaseID: contentReleaseID,
                      contentReleaseRevision: contentReleaseRevision,
                      contentReleaseSHA256: contentReleaseSHA256,
                      contentManifestSHA256: contentManifestSHA256,
                      pageCount: pageCount,
                      placements: placements,
                      rebasePreview: rebasePreview,
                      rebaseReceipt: rebaseReceipt,
                      historicDisplayIsFrozen: historicDisplayIsFrozen,
                      previewIsNotApplied: previewIsNotApplied
                  )
              )) else {
            throw PlanReportProjectionFailureV1.invalidDigest
        }
    }
}

enum PlanReportProjectionPolicyV1 {
    static let sectionID = "plan"
    static let projectionVersion = PlanReportProjectionV1.projectionVersion
    static let supportedFormats: [ReportProjectionFormatV1] = [.openJSON, .pdf, .structuredText]
    static let metadataOnly = true
    static let normalizedPlacementsOnly = true
    static let historicDisplayIsFrozen = true
    static let previewIsNotApplied = true
    static let excludesSourceBytes = true
    static let excludesPrivateLocator = true
    static let excludesActorIdentity = true
    static let excludesUnsupportedClaims = true

    static func supports(_ format: ReportProjectionFormatV1) -> Bool {
        supportedFormats.contains(format)
    }

    static func validate(
        _ projection: PlanReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> PlanReportProjectionV1 {
        guard supports(format), metadataOnly, normalizedPlacementsOnly,
              historicDisplayIsFrozen, previewIsNotApplied,
              excludesSourceBytes, excludesPrivateLocator,
              excludesActorIdentity, excludesUnsupportedClaims else {
            throw PlanReportProjectionFailureV1.unsupportedFormat
        }
        try projection.validate()
        return projection
    }
}

// MARK: - C37 reference-framed placement-pose projection

/// Report-facing frame labels are a closed projection over the canonical pose
/// enum. They are deliberately not compass prose: TRUE, MAGNETIC, and
/// PLAN_RELATIVE remain distinguishable recorded reference frames.
enum C37PoseReferenceFrameProjectionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case trueBearing = "TRUE"
    case magneticBearing = "MAGNETIC"
    case planRelative = "PLAN_RELATIVE"
    case unknown = "UNKNOWN"

    init(_ value: PoseReferenceFrameV1) {
        switch value {
        case .trueBearing: self = .trueBearing
        case .magneticBearing: self = .magneticBearing
        case .planRelative: self = .planRelative
        case .unknown: self = .unknown
        }
    }
}

/// A report can state that a pose was not observed without turning that fact
/// into a claim about alignment or correctness. Manual input remains a
/// separately visible fallback state and unknown uncertainty is explicit.
enum C37PoseObservationStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case observed = "OBSERVED"
    case notObserved = "NOT_OBSERVED"
    case manualFallback = "MANUAL_FALLBACK"
    case uncertaintyUnknown = "UNCERTAINTY_UNKNOWN"
    case reviewRequired = "REVIEW_REQUIRED"
}

enum C37PoseUncertaintyStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case known = "KNOWN"
    case unknown = "UNKNOWN"
}

struct C37PoseHistoryProjectionV1: Codable, Equatable, Hashable, Sendable {
    let eventID: UUID
    let axisID: String
    let placementEpisodeID: UUID
    let placementEventID: UUID
    let rootObservationEventID: UUID
    let rootObservedAt: Date
    let occurredAt: Date
    let recordedAt: Date
    let referenceFrame: C37PoseReferenceFrameProjectionV1
    let disposition: PoseObservationDispositionV1
    let observationState: C37PoseObservationStateV1
    let notObservedReason: PoseNotObservedReasonV1?
    let azimuthMilliDegrees: Int32?
    let elevationMilliDegrees: Int32?
    let horizontalUncertaintyMilliDegrees: Int32?
    let verticalUncertaintyMilliDegrees: Int32?
    let horizontalUncertaintyState: C37PoseUncertaintyStateV1
    let verticalUncertaintyState: C37PoseUncertaintyStateV1
    let source: PoseObservationSourceV1
    let revision: UInt64
    let eventSHA256: String
    let planRevisionID: UUID?
    let planPageID: UUID?
    let planSpatialFrameID: UUID?
    let planTransformSHA256: String?

    init(event: AssetPoseEventV1) throws {
        try event.validateIntrinsic()
        eventID = event.eventID
        axisID = event.axisDescriptor.axisID.rawValue
        placementEpisodeID = event.placementEpisodeID.rawValue
        placementEventID = event.placementEventID
        rootObservationEventID = event.rootObservationEventID
        rootObservedAt = event.rootObservedAt
        occurredAt = event.occurredAt
        recordedAt = event.recordedAt
        referenceFrame = C37PoseReferenceFrameProjectionV1(event.pose.referenceFrame)
        disposition = event.pose.disposition
        notObservedReason = event.pose.notObservedReason
        azimuthMilliDegrees = event.pose.azimuth?.milliDegrees
        elevationMilliDegrees = event.pose.elevation?.milliDegrees
        horizontalUncertaintyMilliDegrees = Self.uncertaintyValue(event.pose.horizontalUncertainty)
        verticalUncertaintyMilliDegrees = Self.uncertaintyValue(event.pose.verticalUncertainty)
        horizontalUncertaintyState = Self.uncertaintyState(event.pose.horizontalUncertainty)
        verticalUncertaintyState = Self.uncertaintyState(event.pose.verticalUncertainty)
        source = event.source
        revision = event.revision
        eventSHA256 = event.eventSHA256
        if case .planRelative(let frame) = event.pose.referenceFrame {
            planRevisionID = frame.planRevision.planRevisionID
            planPageID = frame.pageID
            planSpatialFrameID = frame.spatialFrameID
            planTransformSHA256 = frame.acceptedTransformSHA256
        } else {
            planRevisionID = nil
            planPageID = nil
            planSpatialFrameID = nil
            planTransformSHA256 = nil
        }
        if event.pose.disposition == .notObserved {
            observationState = .notObserved
        } else if event.source == .manual {
            observationState = .manualFallback
        } else if Self.isUnknown(event.pose.horizontalUncertainty)
                    || Self.isUnknown(event.pose.verticalUncertainty) {
            observationState = .uncertaintyUnknown
        } else {
            observationState = .observed
        }
    }

    private static func uncertaintyValue(_ value: PoseUncertaintyV1?) -> Int32? {
        guard case .some(.known(let angle)) = value else { return nil }
        return angle.milliDegrees
    }

    private static func isUnknown(_ value: PoseUncertaintyV1?) -> Bool {
        guard case .some(.unknown) = value else { return false }
        return true
    }

    private static func uncertaintyState(_ value: PoseUncertaintyV1?) -> C37PoseUncertaintyStateV1 {
        guard case .some(.known) = value else { return .unknown }
        return .known
    }

    func validate() throws {
        try PlacementPoseLimitsV1.id(eventID)
        try PlacementPoseLimitsV1.token(axisID)
        try PlacementPoseLimitsV1.id(placementEpisodeID)
        try PlacementPoseLimitsV1.id(placementEventID)
        try PlacementPoseLimitsV1.id(rootObservationEventID)
        try PlacementPoseLimitsV1.digest(eventSHA256)
        try planRevisionID.map(PlacementPoseLimitsV1.id)
        try planPageID.map(PlacementPoseLimitsV1.id)
        try planSpatialFrameID.map(PlacementPoseLimitsV1.id)
        try planTransformSHA256.map(PlacementPoseLimitsV1.digest)
        let usesPlanRelativeFrame: Bool
        if case .planRelative = referenceFrame {
            usesPlanRelativeFrame = true
        } else {
            usesPlanRelativeFrame = false
        }
        let hasValidAzimuth = azimuthMilliDegrees.map { (0..<360_000).contains($0) } ?? true
        let hasValidElevation = elevationMilliDegrees.map { (-90_000...90_000).contains($0) } ?? true
        let hasValidHorizontalUncertainty = horizontalUncertaintyMilliDegrees
            .map { (0...180_000).contains($0) } ?? true
        let hasValidVerticalUncertainty = verticalUncertaintyMilliDegrees
            .map { (0...90_000).contains($0) } ?? true
        guard revision > 0,
              revision <= UInt64(Int.max),
              hasValidAzimuth,
              hasValidElevation,
              hasValidHorizontalUncertainty,
              hasValidVerticalUncertainty,
              (horizontalUncertaintyState == .known)
                  == (horizontalUncertaintyMilliDegrees != nil),
              (verticalUncertaintyState == .known)
                  == (verticalUncertaintyMilliDegrees != nil),
              (observationState == .manualFallback)
                  == (source == .manual && disposition != .notObserved),
              rootObservedAt.timeIntervalSinceReferenceDate.isFinite,
              occurredAt.timeIntervalSinceReferenceDate.isFinite,
              recordedAt.timeIntervalSinceReferenceDate.isFinite,
              rootObservedAt <= occurredAt,
              occurredAt <= recordedAt,
              usesPlanRelativeFrame == (planRevisionID != nil),
              usesPlanRelativeFrame == (planPageID != nil),
              usesPlanRelativeFrame == (planSpatialFrameID != nil),
              usesPlanRelativeFrame == (planTransformSHA256 != nil),
              (disposition == .notObserved) == (observationState == .notObserved),
              !(observationState == .observed &&
                (horizontalUncertaintyState == .unknown || verticalUncertaintyState == .unknown) ) ||
                observationState == .uncertaintyUnknown ||
                observationState == .manualFallback ||
                observationState == .notObserved else {
            throw C37PoseReportProjectionFailureV1.invalidValue
        }
        if disposition == .notObserved {
            guard referenceFrame == .unknown,
                  azimuthMilliDegrees == nil,
                  elevationMilliDegrees == nil,
                  notObservedReason != nil else {
                throw C37PoseReportProjectionFailureV1.invalidValue
            }
        } else {
            guard referenceFrame != .unknown,
                  notObservedReason == nil,
                  azimuthMilliDegrees != nil,
                  horizontalUncertaintyState != .unknown else {
                throw C37PoseReportProjectionFailureV1.invalidValue
            }
        }
    }
}

struct C37PlacementPoseReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let projectionVersion = "c37-placement-pose-report-v1"

    let schemaVersion: Int
    let projectionVersion: String
    let workspaceID: WorkspaceID
    let assetID: UUID
    let currentTipReferences: [AssetPoseEventReferenceV1]
    let history: [C37PoseHistoryProjectionV1]
    let capturedAt: Date
    let historyFrozen: Bool
    let rebasePreviewIsNotApplied: Bool
    let sensorInputAllowed: Bool
    let networkInputAllowed: Bool
    let projectionSHA256: String

    init(workspaceID: WorkspaceID, assetID: UUID,
         events: [AssetPoseEventV1], capturedAt: Date) throws {
        try PlacementPoseLimitsV1.id(workspaceID.rawValue)
        try PlacementPoseLimitsV1.id(assetID)
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite,
              events.count <= PlacementPoseLimitsV1.maximumEventsPerClosure else {
            throw C37PoseReportProjectionFailureV1.invalidValue
        }
        let orderedEvents = events.sorted {
            ($0.axisDescriptor.axisID.rawValue, $0.revision, $0.eventID.uuidString)
                < ($1.axisDescriptor.axisID.rawValue, $1.revision, $1.eventID.uuidString)
        }
        guard orderedEvents.allSatisfy({
            $0.workspaceID == workspaceID && $0.assetID == assetID
        }) else {
            throw C37PoseReportProjectionFailureV1.wrongWorkspace
        }
        if orderedEvents.isEmpty {
            currentTipReferences = []
        } else {
            currentTipReferences = try AssetPoseHistoryV1.currentTip(
                workspaceID: workspaceID, assetID: assetID, events: orderedEvents
            ).tips
        }
        history = try orderedEvents.map(C37PoseHistoryProjectionV1.init(event:))
        schemaVersion = Self.schemaVersion
        projectionVersion = Self.projectionVersion
        self.workspaceID = workspaceID
        self.assetID = assetID
        self.capturedAt = capturedAt
        historyFrozen = true
        rebasePreviewIsNotApplied = true
        sensorInputAllowed = false
        networkInputAllowed = false
        projectionSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                schemaVersion: schemaVersion,
                projectionVersion: projectionVersion,
                workspaceID: workspaceID,
                assetID: assetID,
                currentTipReferences: currentTipReferences,
                history: history,
                capturedAt: capturedAt,
                historyFrozen: historyFrozen,
                rebasePreviewIsNotApplied: rebasePreviewIsNotApplied,
                sensorInputAllowed: sensorInputAllowed,
                networkInputAllowed: networkInputAllowed
            )
        )
        try validate()
    }

    func validate() throws {
        try PlacementPoseLimitsV1.id(workspaceID.rawValue)
        try PlacementPoseLimitsV1.id(assetID)
        try history.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion,
              projectionVersion == Self.projectionVersion,
              capturedAt.timeIntervalSinceReferenceDate.isFinite,
              history == history.sorted(by: {
                  ($0.axisID, $0.revision, $0.eventID.uuidString)
                      < ($1.axisID, $1.revision, $1.eventID.uuidString)
              }),
              Set(history.map(\.eventID)).count == history.count,
              currentTipReferences == currentTipReferences.sorted(by: {
                  ($0.axisID, $0.revision, $0.eventID.uuidString)
                      < ($1.axisID, $1.revision, $1.eventID.uuidString)
              }),
              Set(currentTipReferences.map(\.axisID)).count == currentTipReferences.count,
              currentTipReferences.allSatisfy({ reference in
                  reference.workspaceID == workspaceID && reference.assetID == assetID
                      && history.contains(where: {
                          $0.eventID == reference.eventID
                              && $0.axisID == reference.axisID
                              && $0.revision == reference.revision
                              && $0.eventSHA256 == reference.eventSHA256
                      })
              }),
              historyFrozen,
              rebasePreviewIsNotApplied,
              !sensorInputAllowed,
              !networkInputAllowed,
              projectionSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                  DigestBasis(
                      schemaVersion: schemaVersion,
                      projectionVersion: projectionVersion,
                      workspaceID: workspaceID,
                      assetID: assetID,
                      currentTipReferences: currentTipReferences,
                      history: history,
                      capturedAt: capturedAt,
                      historyFrozen: historyFrozen,
                      rebasePreviewIsNotApplied: rebasePreviewIsNotApplied,
                      sensorInputAllowed: sensorInputAllowed,
                      networkInputAllowed: networkInputAllowed
                  )
              )) else {
            throw C37PoseReportProjectionFailureV1.invalidDigest
        }
        try currentTipReferences.forEach { try $0.validate() }
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let projectionVersion: String
        let workspaceID: WorkspaceID
        let assetID: UUID
        let currentTipReferences: [AssetPoseEventReferenceV1]
        let history: [C37PoseHistoryProjectionV1]
        let capturedAt: Date
        let historyFrozen: Bool
        let rebasePreviewIsNotApplied: Bool
        let sensorInputAllowed: Bool
        let networkInputAllowed: Bool
    }
}

struct C37PlacementPoseFrozenSnapshotV1: Codable, Equatable, Sendable {
    let sourceSnapshotID: UUID
    let projection: C37PlacementPoseReportProjectionV1
    let historicDisplayIsFrozen: Bool
    let snapshotSHA256: String

    init(sourceSnapshotID: UUID,
         projection: C37PlacementPoseReportProjectionV1) throws {
        try PlacementPoseLimitsV1.id(sourceSnapshotID)
        try projection.validate()
        self.sourceSnapshotID = sourceSnapshotID
        self.projection = projection
        historicDisplayIsFrozen = true
        snapshotSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                sourceSnapshotID: sourceSnapshotID,
                projection: projection,
                historicDisplayIsFrozen: historicDisplayIsFrozen
            )
        )
        try validate()
    }

    func validate() throws {
        try PlacementPoseLimitsV1.id(sourceSnapshotID)
        try projection.validate()
        guard historicDisplayIsFrozen,
              snapshotSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                  DigestBasis(
                      sourceSnapshotID: sourceSnapshotID,
                      projection: projection,
                      historicDisplayIsFrozen: historicDisplayIsFrozen
                  )
              )) else {
            throw C37PoseReportProjectionFailureV1.invalidDigest
        }
    }

    private struct DigestBasis: Codable {
        let sourceSnapshotID: UUID
        let projection: C37PlacementPoseReportProjectionV1
        let historicDisplayIsFrozen: Bool
    }
}

enum C37PoseReportProjectionFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidDigest
    case wrongWorkspace
    case staleHistory
    case privacyViolation
    case unsupportedClaim
}

enum C37PoseReportProjectionPolicyV1 {
    static let metadataOnly = true
    static let currentAndHistoryAreRecordedFacts = true
    static let historyFrozen = true
    static let rebasePreviewIsNotApplied = true
    static let excludesSensorInput = true
    static let excludesNetworkInput = true
    static let excludesActorIdentity = true
    static let excludesPrivateLocators = true
    static let excludesSourceBytes = true
    static let excludesUnsupportedClaims = true

    static func validate(_ projection: C37PlacementPoseReportProjectionV1) throws {
        guard metadataOnly, currentAndHistoryAreRecordedFacts, historyFrozen,
              rebasePreviewIsNotApplied, excludesSensorInput, excludesNetworkInput,
              excludesActorIdentity, excludesPrivateLocators, excludesSourceBytes,
              excludesUnsupportedClaims else {
            throw C37PoseReportProjectionFailureV1.privacyViolation
        }
        try projection.validate()
    }
}

// MARK: - C30 operating-context consumer projection

/// A report-safe view of the C30 durable evidence context.  It deliberately
/// preserves the user-observed lighting condition and the optional solar
/// calculation as separate facts.  Consumers must never derive a lighting
/// condition from a timestamp, image, or calculation, and an expected control
/// state is not an observation of the control.
struct C30EvidenceContextReportReferenceV1: Codable, Equatable, Sendable {
    static let schemaVersion = "C30_EVIDENCE_CONTEXT_REPORT_V1"

    let schemaVersion: String
    let contextID: UUID
    let workspaceID: WorkspaceID
    let evidenceID: String
    let evidenceSHA256: String
    let evidenceRevision: UInt64
    let assetID: UUID
    let assetRevision: UInt64
    let contextRevision: UInt64
    let temporalContext: TemporalContextV1
    let observedCondition: EvidenceLightingConditionV1
    let derivedCondition: DerivedSolarConditionV1?
    let derivedPolarDisposition: SolarPolarDispositionV1?
    let expectedControlState: ExpectedControlStateV1?
    let pairedObservation: C30PairedObservationReportReferenceV1?
    let contextSHA256: String
    let frozenDisplay: Bool

    init(
        context: EvidenceContextV1,
        pairedObservation: PairedObservationLinkV1? = nil
    ) throws {
        try context.validateIntrinsic()
        if let pairedObservation {
            try pairedObservation.validateIntrinsic()
            guard pairedObservation.first.evidenceID == context.evidenceID
                    || pairedObservation.second.evidenceID == context.evidenceID else {
                throw C30ConsumerProjectionFailureV1.referenceMismatch
            }
        }
        schemaVersion = Self.schemaVersion
        contextID = context.contextID
        workspaceID = context.workspaceID
        evidenceID = context.evidenceID
        evidenceSHA256 = context.evidenceSHA256
        evidenceRevision = context.evidenceRevision
        assetID = context.assetID
        assetRevision = context.assetRevision
        contextRevision = context.revision
        temporalContext = context.temporalContext
        observedCondition = context.userObserved.condition
        derivedCondition = context.derivedSolar?.derivedCondition
        derivedPolarDisposition = context.derivedSolar?.polarDisposition
        expectedControlState = context.controlExpectation?.expectedState
        self.pairedObservation = try pairedObservation.map {
            try C30PairedObservationReportReferenceV1($0, context: context)
        }
        contextSHA256 = context.contextSHA256
        frozenDisplay = true
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              workspaceID.rawValue != SearchContractValidationV1.zeroUUID,
              contextID != SearchContractValidationV1.zeroUUID,
              assetID != SearchContractValidationV1.zeroUUID,
              SearchContractValidationV1.validID(evidenceID),
              KernelCanonicalHashV1.validSHA256(evidenceSHA256),
              evidenceRevision > 0, assetRevision > 0,
              contextRevision > 0, frozenDisplay,
              KernelCanonicalHashV1.validSHA256(contextSHA256),
              (derivedCondition == nil) == (derivedPolarDisposition == nil) else {
            throw C30ConsumerProjectionFailureV1.invalidValue
        }
        try temporalContext.validate()
        try pairedObservation?.validate(boundTo: self)
        try C30OperatingContextConsumerPolicyV1.validate(self)
    }
}

/// The endpoint facts needed to re-bind a decoded pair without carrying
/// actor, mutation, or source-byte data into a report.  Link compatibility
/// depends on these fields, so they remain part of the frozen projection.
struct C30PairedObservationEndpointBindingV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let evidenceID: String
    let evidenceSHA256: String
    let evidenceRevision: UInt64
    let assetID: UUID
    let assetRevision: UInt64
    let controlGroupID: String
    let purpose: PairedObservationPurposeV1
    let purposeRevision: UInt64
    let planReferenceSHA256: String?
    let viewpointReferenceSHA256: String
    let temporalBucketID: String
    let surfaceWeatherBasisSHA256: String
    let measurementMethodID: String

    init(_ reference: PairedObservationReferenceV1) {
        workspaceID = reference.workspaceID
        evidenceID = reference.evidenceID
        evidenceSHA256 = reference.evidenceSHA256
        evidenceRevision = reference.evidenceRevision
        assetID = reference.assetID
        assetRevision = reference.assetRevision
        controlGroupID = reference.controlGroupID
        purpose = reference.purpose
        purposeRevision = reference.purposeRevision
        planReferenceSHA256 = reference.planReferenceSHA256
        viewpointReferenceSHA256 = reference.viewpointReferenceSHA256
        temporalBucketID = reference.temporalBucketID
        surfaceWeatherBasisSHA256 = reference.surfaceWeatherBasisSHA256
        measurementMethodID = reference.measurementMethodID
    }

    func coreReference() -> PairedObservationReferenceV1 {
        PairedObservationReferenceV1(
            workspaceID: workspaceID,
            evidenceID: evidenceID,
            evidenceSHA256: evidenceSHA256,
            evidenceRevision: evidenceRevision,
            assetID: assetID,
            assetRevision: assetRevision,
            controlGroupID: controlGroupID,
            purpose: purpose,
            purposeRevision: purposeRevision,
            planReferenceSHA256: planReferenceSHA256,
            viewpointReferenceSHA256: viewpointReferenceSHA256,
            temporalBucketID: temporalBucketID,
            surfaceWeatherBasisSHA256: surfaceWeatherBasisSHA256,
            measurementMethodID: measurementMethodID
        )
    }

    func validate() throws {
        guard workspaceID.rawValue != SearchContractValidationV1.zeroUUID,
              assetID != SearchContractValidationV1.zeroUUID else {
            throw C30ConsumerProjectionFailureV1.invalidValue
        }
        try coreReference().validate()
    }
}

struct C30PairedObservationReportReferenceV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let contextID: UUID
    let contextSHA256: String
    let contextRevision: UInt64
    let evidenceID: String
    let evidenceSHA256: String
    let evidenceRevision: UInt64
    let assetID: UUID
    let assetRevision: UInt64
    let linkID: UUID
    let firstEvidenceID: String
    let secondEvidenceID: String
    let firstEndpoint: C30PairedObservationEndpointBindingV1
    let secondEndpoint: C30PairedObservationEndpointBindingV1
    let purpose: PairedObservationPurposeV1
    let mismatchReasons: [PairedObservationMismatchReasonV1]
    let revision: UInt64
    let linkSHA256: String

    init(_ link: PairedObservationLinkV1, context: EvidenceContextV1) throws {
        try link.validateIntrinsic()
        let matchingEndpoints = [link.first, link.second]
            .filter { $0.evidenceID == context.evidenceID }
        guard matchingEndpoints.count == 1,
              let matchingEndpoint = matchingEndpoints.first,
              matchingEndpoint.workspaceID == context.workspaceID,
              matchingEndpoint.evidenceSHA256 == context.evidenceSHA256,
              matchingEndpoint.evidenceRevision == context.evidenceRevision,
              matchingEndpoint.assetID == context.assetID,
              matchingEndpoint.assetRevision == context.assetRevision else {
            throw C30ConsumerProjectionFailureV1.referenceMismatch
        }
        workspaceID = context.workspaceID
        contextID = context.contextID
        contextSHA256 = context.contextSHA256
        contextRevision = context.revision
        evidenceID = context.evidenceID
        evidenceSHA256 = context.evidenceSHA256
        evidenceRevision = context.evidenceRevision
        assetID = context.assetID
        assetRevision = context.assetRevision
        linkID = link.linkID
        firstEvidenceID = link.first.evidenceID
        secondEvidenceID = link.second.evidenceID
        firstEndpoint = C30PairedObservationEndpointBindingV1(link.first)
        secondEndpoint = C30PairedObservationEndpointBindingV1(link.second)
        purpose = link.first.purpose
        mismatchReasons = link.mismatchReasons
        revision = link.revision
        linkSHA256 = link.linkSHA256
        try validate(boundTo: context)
    }

    var isComparable: Bool { mismatchReasons.isEmpty }

    var disposition: C30PairedComparisonDispositionV1 {
        isComparable ? .comparable : .mismatch
    }

    func validate() throws {
        guard workspaceID.rawValue != SearchContractValidationV1.zeroUUID,
              contextID != SearchContractValidationV1.zeroUUID,
              KernelCanonicalHashV1.validSHA256(contextSHA256),
              SearchContractValidationV1.validID(evidenceID),
              KernelCanonicalHashV1.validSHA256(evidenceSHA256),
              evidenceRevision > 0, assetID != SearchContractValidationV1.zeroUUID,
              assetRevision > 0,
              linkID != SearchContractValidationV1.zeroUUID,
              firstEvidenceID == firstEndpoint.evidenceID,
              secondEvidenceID == secondEndpoint.evidenceID,
              firstEvidenceID != secondEvidenceID,
              firstEndpoint.workspaceID == workspaceID,
              secondEndpoint.workspaceID == workspaceID,
              firstEndpoint.assetID == assetID,
              secondEndpoint.assetID == assetID,
              firstEndpoint.evidenceID != secondEndpoint.evidenceID,
              purpose == firstEndpoint.purpose,
              revision > 0, mismatchReasons == mismatchReasons.sorted(),
              Set(mismatchReasons).count == mismatchReasons.count,
              KernelCanonicalHashV1.validSHA256(linkSHA256) else {
            throw C30ConsumerProjectionFailureV1.invalidValue
        }
        try firstEndpoint.validate()
        try secondEndpoint.validate()
        let first = firstEndpoint.coreReference()
        let second = secondEndpoint.coreReference()
        guard PairedObservationLinkV1.mismatches(first, second) == mismatchReasons else {
            throw C30ConsumerProjectionFailureV1.referenceMismatch
        }
    }

    func validate(boundTo context: EvidenceContextV1) throws {
        try validate()
        let bound = [firstEndpoint, secondEndpoint]
            .filter { $0.evidenceID == evidenceID }
        guard bound.count == 1,
              workspaceID == context.workspaceID,
              contextID == context.contextID,
              contextSHA256 == context.contextSHA256,
              contextRevision == context.revision,
              evidenceID == context.evidenceID,
              evidenceSHA256 == context.evidenceSHA256,
              evidenceRevision == context.evidenceRevision,
              assetID == context.assetID,
              assetRevision == context.assetRevision,
              let endpoint = bound.first,
              endpoint.workspaceID == context.workspaceID,
              endpoint.evidenceID == context.evidenceID,
              endpoint.evidenceSHA256 == context.evidenceSHA256,
              endpoint.evidenceRevision == context.evidenceRevision,
              endpoint.assetID == context.assetID,
              endpoint.assetRevision == context.assetRevision else {
            throw C30ConsumerProjectionFailureV1.referenceMismatch
        }
    }

    func validate(boundTo projection: C30EvidenceContextReportReferenceV1) throws {
        try validate()
        let bound = [firstEndpoint, secondEndpoint]
            .filter { $0.evidenceID == evidenceID }
        guard bound.count == 1,
              workspaceID == projection.workspaceID,
              contextID == projection.contextID,
              contextSHA256 == projection.contextSHA256,
              contextRevision == projection.contextRevision,
              evidenceID == projection.evidenceID,
              evidenceSHA256 == projection.evidenceSHA256,
              evidenceRevision == projection.evidenceRevision,
              assetID == projection.assetID,
              assetRevision == projection.assetRevision,
              let endpoint = bound.first,
              endpoint.workspaceID == projection.workspaceID,
              endpoint.evidenceID == projection.evidenceID,
              endpoint.evidenceSHA256 == projection.evidenceSHA256,
              endpoint.evidenceRevision == projection.evidenceRevision,
              endpoint.assetID == projection.assetID,
              endpoint.assetRevision == projection.assetRevision else {
            throw C30ConsumerProjectionFailureV1.referenceMismatch
        }
    }
}

enum C30PairedComparisonDispositionV1: String, Codable, CaseIterable, Sendable {
    case comparable = "COMPARABLE"
    case mismatch = "MISMATCH"
    case notLinked = "NOT_LINKED"
}

enum C30ConsumerProjectionFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case referenceMismatch
    case unsupportedClaim
    case privacyViolation
}

enum C30OperatingContextConsumerPolicyV1 {
    static let metadataOnly = true
    static let userObservedConditionRemainsSeparate = true
    static let solarCalculationRemainsSeparate = true
    static let timestampDoesNotInferCondition = true
    static let photoDoesNotInferCondition = true
    static let expectedControlIsNotActualControl = true
    static let pairedComparisonCarriesReasons = true
    static let historicDisplayIsFrozen = true
    static let originalsAndManualOfflinePathPreserved = true
    static let noSensorOrNetworkCollection = true
    static let noOperationalFailureOrComplianceClaims = true

    static func validate(_ projection: C30EvidenceContextReportReferenceV1) throws {
        guard metadataOnly, userObservedConditionRemainsSeparate,
              solarCalculationRemainsSeparate, timestampDoesNotInferCondition,
              photoDoesNotInferCondition, expectedControlIsNotActualControl,
              pairedComparisonCarriesReasons, historicDisplayIsFrozen,
              originalsAndManualOfflinePathPreserved, noSensorOrNetworkCollection,
              noOperationalFailureOrComplianceClaims else {
            throw C30ConsumerProjectionFailureV1.privacyViolation
        }
        guard projection.frozenDisplay else {
            throw C30ConsumerProjectionFailureV1.unsupportedClaim
        }
        try projection.pairedObservation?.validate()
    }
}

enum C30ConsumerRoleV1: String, Codable, CaseIterable, Sendable {
    case evidence = "EVIDENCE"
    case report = "REPORT"
    case search = "SEARCH"
    case localization = "LOCALIZATION"
    case accessibility = "ACCESSIBILITY"
    case content = "CONTENT"
    case camera = "CAMERA"
    case feature = "FEATURE"
    case asset = "ASSET"
    case draft = "DRAFT"
    case location = "LOCATION"
    case pack = "PACK"
    case plan = "PLAN"
    case pose = "POSE"
    case workPacket = "WORK_PACKET"
    case survey = "SURVEY"
    case checkRunner = "CHECK_RUNNER"
    case job = "JOB"
    case port = "PORT"
    case lifecycle = "LIFECYCLE"
    case finalization = "FINALIZATION"
    case compatibility = "COMPATIBILITY"
    case media = "MEDIA"
}

/// Registration used by consumer seams.  It is intentionally a projection
/// contract rather than a second evidence-context writer or persistence model.
struct C30ConsumerRegistrationV1: Codable, Equatable, Sendable {
    let ownerPath: String
    let role: C30ConsumerRoleV1
    let readsFrozenContextProjection: Bool
    let preservesOriginalEvidence: Bool
    let preservesManualOfflinePath: Bool
    let forbidsTimestampPhotoSolarInference: Bool
    let forbidsActualControlFailureComplianceClaims: Bool

    init(ownerPath: String, role: C30ConsumerRoleV1) {
        self.ownerPath = ownerPath
        self.role = role
        readsFrozenContextProjection = true
        preservesOriginalEvidence = true
        preservesManualOfflinePath = true
        forbidsTimestampPhotoSolarInference = true
        forbidsActualControlFailureComplianceClaims = true
    }

    func validate() throws {
        guard !ownerPath.isEmpty, readsFrozenContextProjection,
              preservesOriginalEvidence, preservesManualOfflinePath,
              forbidsTimestampPhotoSolarInference,
              forbidsActualControlFailureComplianceClaims else {
            throw C30ConsumerProjectionFailureV1.invalidValue
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Domain_Reporting_ReportProjectionContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift", role: .report)
}

// MARK: - C31 exterior/parking-lighting consumer projection

/// Closed claim vocabulary for the C31 consumer surfaces.  These values are
/// descriptions of recorded facts and references; they are deliberately not
/// pass/fail, safety, compliance, security, or professional conclusions.
enum C31LightingClaimBoundaryV1: String, Codable, CaseIterable, Hashable, Sendable {
    case noClaimRecorded = "NO_CLAIM_RECORDED"
    case observationOnly = "OBSERVATION_ONLY"
    case measuredWithRecordedInputs = "MEASURED_WITH_RECORDED_INPUTS"
    case criterionReferenceRecorded = "CRITERION_REFERENCE_RECORDED"
    case externalEvidenceReferenceRecorded = "EXTERNAL_EVIDENCE_REFERENCE_RECORDED"
    case mixedRecordedFacts = "MIXED_RECORDED_FACTS"

    static func from(_ claims: [LightingClaimStateV1]) -> Self {
        guard !claims.isEmpty else { return .noClaimRecorded }
        let tiers = Set(claims.map(\.tier))
        guard tiers.count == 1, let tier = tiers.first else { return .mixedRecordedFacts }
        switch tier {
        case .observed: return .observationOnly
        case .measured, .derived: return .measuredWithRecordedInputs
        case .screened: return .criterionReferenceRecorded
        case .externallyAttested: return .externalEvidenceReferenceRecorded
        }
    }
}

/// Immutable, bounded, metadata-only C31 projection used by reports, export,
/// and search consumers.  It contains no actor identity, content bytes,
/// private locators, notes, or inferred equipment state.
struct C31LightingReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let systemID: UUID
    let systemRevision: UInt64
    let systemSHA256: String
    let packageReleaseID: String
    let zoneCount: Int
    let controlGroupCount: Int
    let luminaireCount: Int
    let observationCount: Int
    let issueCount: Int
    let measurementPlanCount: Int
    let claimCount: Int
    let measuredClaimCount: Int
    let criterionBoundClaimCount: Int
    let captureBindingCount: Int
    let issueKinds: [LightingIssueKindV1]
    let claimTiers: [LightingClaimTierV1]
    let issueDispositions: [LightingIssueDispositionV1]
    let safetyStopReasons: [LightingSafetyStopReasonV1]
    let claimBoundary: C31LightingClaimBoundaryV1
    let frozenDisplay: Bool
    let preservesOriginalEvidence: Bool
    let manualOfflinePathPreserved: Bool

    init(
        system: LightingSystemV1,
        observations: [LightingObservationV1] = [],
        issues: [LightingIssueV1] = [],
        measurementPlans: [MeasurementPlanV1] = [],
        claims: [LightingClaimStateV1] = [],
        safetyStopReasons: [LightingSafetyStopReasonV1] = []
    ) throws {
        try system.validateIntrinsic()
        try observations.forEach { try $0.validate(system: system) }
        try issues.forEach { try $0.validateIntrinsic() }
        try measurementPlans.forEach { try $0.validate(system: system) }
        try claims.forEach { try $0.validateIntrinsic() }
        guard observations.allSatisfy({ $0.workspaceID == system.workspaceID }),
              issues.allSatisfy({ $0.workspaceID == system.workspaceID }),
              measurementPlans.allSatisfy({ $0.workspaceID == system.workspaceID }),
              claims.allSatisfy({ $0.workspaceID == system.workspaceID }) else {
            throw SnapshotProjectionFailureV1.wrongWorkspace
        }

        schemaVersion = Self.schemaVersion
        workspaceID = system.workspaceID
        systemID = system.systemID
        systemRevision = system.revision
        systemSHA256 = system.systemSHA256
        packageReleaseID = system.packageRelease.packageReleaseID
        zoneCount = system.zones.count
        controlGroupCount = system.controlGroups.count
        luminaireCount = system.luminaires.count
        observationCount = observations.count
        issueCount = issues.count
        measurementPlanCount = measurementPlans.count
        claimCount = claims.count
        measuredClaimCount = claims.filter { $0.measurement != nil }.count
        criterionBoundClaimCount = claims.filter { $0.criterion != nil }.count
        captureBindingCount = claims.reduce(0) { $0 + ($1.measurement?.captures.count ?? 0) }
        issueKinds = Array(Set(issues.map(\.kind))).sorted()
        claimTiers = claims.map(\.tier).sorted { $0.rawValue < $1.rawValue }
        issueDispositions = Array(Set(issues.map(\.disposition))).sorted { $0.rawValue < $1.rawValue }
        self.safetyStopReasons = Array(Set(safetyStopReasons)).sorted { $0.rawValue < $1.rawValue }
        claimBoundary = C31LightingClaimBoundaryV1.from(claims)
        frozenDisplay = true
        preservesOriginalEvidence = true
        manualOfflinePathPreserved = true
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              systemID != LightingLimitsV1.zero,
              systemRevision > 0,
              MutationEnvelopeV1.isSHA256(systemSHA256),
              MutationEnvelopeV1.isSHA256(packageReleaseID),
              [zoneCount, controlGroupCount, luminaireCount, observationCount,
               issueCount, measurementPlanCount, claimCount, measuredClaimCount,
               criterionBoundClaimCount, captureBindingCount]
                .allSatisfy({ $0 >= 0 }),
              zoneCount <= LightingLimitsV1.maximumZones,
              controlGroupCount <= LightingLimitsV1.maximumControlGroups,
              luminaireCount <= LightingLimitsV1.maximumLuminaires,
              observationCount <= LightingLimitsV1.maximumEvidence * LightingLimitsV1.maximumLuminaires,
              issueCount <= LightingLimitsV1.maximumEvidence * LightingLimitsV1.maximumLuminaires,
              measurementPlanCount <= LightingLimitsV1.maximumEvidence,
              claimCount <= LightingLimitsV1.maximumEvidence * LightingLimitsV1.maximumLuminaires,
              measuredClaimCount <= claimCount,
              criterionBoundClaimCount <= claimCount,
              claimTiers == claimTiers.sorted(by: { $0.rawValue < $1.rawValue }),
              issueKinds == issueKinds.sorted(),
              Set(issueKinds).count == issueKinds.count,
              issueDispositions == issueDispositions.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(issueDispositions).count == issueDispositions.count,
              safetyStopReasons == safetyStopReasons.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(safetyStopReasons).count == safetyStopReasons.count,
              ((claimTiers.isEmpty && claimBoundary == .noClaimRecorded)
                || (!claimTiers.isEmpty && claimBoundary != .noClaimRecorded)),
              frozenDisplay, preservesOriginalEvidence, manualOfflinePathPreserved else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

enum C31LightingProjectionPolicyV1 {
    static let metadataOnly = true
    static let preservesOriginalEvidence = true
    static let historicDisplayFrozen = true
    static let manualOfflinePathPreserved = true
    static let excludesActorIdentity = true
    static let excludesContentBytesAndPrivateLocators = true
    static let excludesOperationalSafetySecurityComplianceClaims = true
    static let excludesTimestampPhotoSolarInference = true
    static let forbiddenClaimPhrases = [
        "compliance", "safety certified", "security certified", "ies compliant",
        "ada compliant", "verified safe", "operational failure", "actual control",
        "photo proves", "timestamp proves", "darkness inferred", "survey-grade",
        "gis", "cad", "bim", "lidar", "remote delivery", "secure",
    ]

    static func validate(_ projection: C31LightingReportProjectionV1) throws {
        try projection.validate()
        guard metadataOnly, preservesOriginalEvidence, historicDisplayFrozen,
              manualOfflinePathPreserved, excludesActorIdentity,
              excludesContentBytesAndPrivateLocators,
              excludesOperationalSafetySecurityComplianceClaims,
              excludesTimestampPhotoSolarInference else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
    }
}

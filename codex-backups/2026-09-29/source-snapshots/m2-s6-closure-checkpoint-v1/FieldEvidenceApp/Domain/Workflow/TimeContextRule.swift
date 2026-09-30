import Foundation

enum ScheduleTimeContextBoundaryV1 { static func validate(_ value: FrozenScheduleTimeBasisV1) throws { try value.validate() } }

enum C34NavigationTimeContextBoundaryV1 {
    static let restorationResolvesCivilTime = false
    static let restorationRebindsTimeZone = false
    static let routeAnchorStoresTimeBasis = false
}

struct FrozenTimeContext: Equatable, Sendable {
    let observedAtUTC: Date
    let timeZoneID: String
    let utcOffsetMinutes: Int
    let localDate: String
    let localTime: String
}

enum C33TemporalEvidenceTimeContextBoundaryV1 { static let clipRelativeOffsetUsesSiteTimeZone=false;static let captureInstantRemainsRecordedContext=true;static let canonicalMutationKind:WorkspaceCommandKindV1 = .applyTemporalEvidence }

enum TimeContextRuleError: Error, Equatable {
    case invalidTimeZoneID
}

enum TimeContextRule {
    struct ScheduleCivilTimeResolutionV1: Equatable, Sendable {
        let resolvedAtUTC: Date?
        let utcOffsetSeconds: Int?
        let disposition: LocalTimeDispositionV1
    }

    /// Resolves one frozen Gregorian/IANA civil time without consulting the
    /// device's current zone. The selected offset and gap/fold disposition are
    /// subsequently carried by OccurrenceScheduleBasisV2 and never recomputed.
    static func resolveScheduleCivilTime(
        date: ScheduleLocalDateV1,
        window: ScheduleLocalAnchorV1,
        timeBasis: FrozenScheduleTimeBasisV1
    ) throws -> ScheduleCivilTimeResolutionV1 {
        try date.validate(); try window.validate(); try timeBasis.validate()
        guard TimeZone.knownTimeZoneIdentifiers.contains(timeBasis.ianaTimeZoneIdentifier),
              let timeZone = TimeZone(identifier: timeBasis.ianaTimeZoneIdentifier) else {
            throw TimeContextRuleError.invalidTimeZoneID
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        var match = DateComponents()
        match.year = date.year; match.month = date.month; match.day = date.day
        match.hour = window.hour; match.minute = window.minute; match.second = window.second
        let priorDay = try scheduleDate(date, addingDays: -1, calendar: calendar)
        let first = calendar.nextDate(after: priorDay, matching: match, matchingPolicy: .strict,
                                      repeatedTimePolicy: .first, direction: .forward)
        let last = calendar.nextDate(after: priorDay, matching: match, matchingPolicy: .strict,
                                     repeatedTimePolicy: .last, direction: .forward)
        let exactFirst = first.flatMap { scheduleComponentsMatch($0, match: match, calendar: calendar) ? $0 : nil }
        let exactLast = last.flatMap { scheduleComponentsMatch($0, match: match, calendar: calendar) ? $0 : nil }
        if let exactFirst, let exactLast {
            let ambiguous = exactFirst != exactLast
            let selected = ambiguous && timeBasis.ambiguousTimePolicy == .laterOffset ? exactLast : exactFirst
            return .init(resolvedAtUTC: selected,
                         utcOffsetSeconds: timeZone.secondsFromGMT(for: selected),
                         disposition: ambiguous ? .ambiguousFold : .unambiguous)
        }
        guard timeBasis.nonexistentTimePolicy == .shiftForwardByGap else {
            return .init(resolvedAtUTC: nil, utcOffsetSeconds: nil, disposition: .nonexistentGap)
        }
        guard let shifted = calendar.nextDate(after: priorDay, matching: match, matchingPolicy: .nextTime,
                                              repeatedTimePolicy: .first, direction: .forward) else {
            throw ScheduleFailureV1.nonexistentLocalTime
        }
        return .init(resolvedAtUTC: shifted,
                     utcOffsetSeconds: timeZone.secondsFromGMT(for: shifted),
                     disposition: .nonexistentGap)
    }

    static func freezeScheduleBasisV2(
        nominalDate: ScheduleLocalDateV1,
        effectiveDate: ScheduleLocalDateV1?,
        nominalWindow: ScheduleLocalAnchorV1,
        effectiveWindow: ScheduleLocalAnchorV1?,
        calendarRelease: ExceptionCalendarReleaseReferenceV1,
        timeBasis: FrozenScheduleTimeBasisV1,
        adjustmentReason: ScheduleBasisAdjustmentReasonV1,
        sourceOverrideEventSHA256: String? = nil,
        predecessorBasisSHA256: String? = nil
    ) throws -> OccurrenceScheduleBasisV2 {
        let resolution: ScheduleCivilTimeResolutionV1
        if let effectiveDate, let effectiveWindow {
            resolution = try resolveScheduleCivilTime(date: effectiveDate, window: effectiveWindow,
                                                      timeBasis: timeBasis)
        } else {
            resolution = .init(resolvedAtUTC: nil, utcOffsetSeconds: nil, disposition: .nonexistentGap)
        }
        return try .init(nominalDate: nominalDate, effectiveDate: effectiveDate,
                         nominalWindow: nominalWindow, effectiveWindow: effectiveWindow,
                         calendarRelease: calendarRelease, timeBasis: timeBasis,
                         resolvedAtUTC: resolution.resolvedAtUTC,
                         resolvedUTCOffsetSeconds: resolution.utcOffsetSeconds,
                         localTimeDisposition: resolution.disposition,
                         adjustmentReason: adjustmentReason,
                         sourceOverrideEventSHA256: sourceOverrideEventSHA256,
                         predecessorBasisSHA256: predecessorBasisSHA256)
    }

    private static func scheduleDate(_ value: ScheduleLocalDateV1, addingDays: Int,
                                     calendar: Calendar) throws -> Date {
        guard let source = calendar.date(from: DateComponents(year: value.year, month: value.month, day: value.day)),
              let result = calendar.date(byAdding: .day, value: addingDays, to: source) else {
            throw ScheduleFailureV1.invalidValue
        }
        return result
    }

    private static func scheduleComponentsMatch(_ value: Date, match: DateComponents,
                                                calendar: Calendar) -> Bool {
        let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: value)
        return actual.year == match.year && actual.month == match.month && actual.day == match.day
            && actual.hour == match.hour && actual.minute == match.minute && actual.second == match.second
    }

    static func freezeTemporalContext(
        occurredAtUTC: Date,
        recordedAtUTC: Date,
        confirmedTimeZoneID: String
    ) throws -> TemporalContextV1 {
        guard TimeZone.knownTimeZoneIdentifiers.contains(confirmedTimeZoneID),
              let timeZone = TimeZone(identifier: confirmedTimeZoneID) else {
            throw TimeContextRuleError.invalidTimeZoneID
        }
        let local = localStrings(for: occurredAtUTC, timeZone: timeZone)
        let disposition: LocalTimeDispositionV1 = isAmbiguousFold(
            occurredAtUTC,
            timeZone: timeZone
        ) ? .ambiguousFold : .unambiguous
        return try TemporalContextV1(
            occurredAtUTC: occurredAtUTC,
            recordedAtUTC: recordedAtUTC,
            localDate: local.date,
            localTime: local.time,
            utcOffsetSeconds: timeZone.secondsFromGMT(for: occurredAtUTC),
            ianaTimeZoneIdentifier: confirmedTimeZoneID,
            localTimeDisposition: disposition
        )
    }

    static func freeze(
        observedAtUTC: Date,
        confirmedTimeZoneID: String
    ) throws -> FrozenTimeContext {
        guard TimeZone.knownTimeZoneIdentifiers.contains(confirmedTimeZoneID),
              let timeZone = TimeZone(identifier: confirmedTimeZoneID) else {
            throw TimeContextRuleError.invalidTimeZoneID
        }

        let local = localStrings(for: observedAtUTC, timeZone: timeZone)

        return FrozenTimeContext(
            observedAtUTC: observedAtUTC,
            timeZoneID: confirmedTimeZoneID,
            utcOffsetMinutes: timeZone.secondsFromGMT(for: observedAtUTC) / 60,
            localDate: local.date,
            localTime: local.time
        )
    }

    private static func localStrings(
        for instant: Date,
        timeZone: TimeZone
    ) -> (date: String, time: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm:ss"
        return (
            dateFormatter.string(from: instant),
            timeFormatter.string(from: instant)
        )
    }

    /// A fold has two UTC instants with the same local civil second. Calendar's
    /// strict first/last policies expose both without treating either as
    /// causal authority.
    private static func isAmbiguousFold(
        _ instant: Date,
        timeZone: TimeZone
    ) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: instant
        )
        let searchStart = instant.addingTimeInterval(-2 * 24 * 60 * 60)
        guard let first = calendar.nextDate(
            after: searchStart,
            matching: components,
            matchingPolicy: .strict,
            repeatedTimePolicy: .first,
            direction: .forward
        ),
        let last = calendar.nextDate(
            after: searchStart,
            matching: components,
            matchingPolicy: .strict,
            repeatedTimePolicy: .last,
            direction: .forward
        ) else { return false }
        return first != last
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Workflow_TimeContextRule {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Workflow_TimeContextRule_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}

enum C30EvidenceContextTimeContextRuleV1 {
    static let daylightConditionIsUserObservedOrOfflineDerived = true
    static let timezoneAndOffsetMustBeRecorded = true
    static let timeDoesNotInferControlCompliance = true

    static func validate(_ value: EvidenceContextV1) throws {
        try value.validateIntrinsic()
        try value.temporalContext.validate()
        guard daylightConditionIsUserObservedOrOfflineDerived,
              timezoneAndOffsetMustBeRecorded, timeDoesNotInferControlCompliance else {
            throw EvidenceContextFailureV1.invalidValue
        }
    }
}

enum C31LightingTimeContextBoundaryV1 {
    static let timestampsRemainRecordedInputs = true
    static let solarValuesAreOfflineDerivedOnly = true
    static let timeDoesNotEstablishLightingCompliance = true

    static func validate(
        records: [V31BackupLightingRecordV1],
        workspaceID: WorkspaceID
    ) throws {
        try C31LightingWorkflowBoundaryV1.validate(
            records: records,
            workspaceID: workspaceID
        )
        guard timestampsRemainRecordedInputs,
              solarValuesAreOfflineDerivedOnly,
              timeDoesNotEstablishLightingCompliance else {
            throw LightingContractFailureV1.invalidValue
        }
    }
}
// MARK: - C32 assistance time context boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Workflow_TimeContextRule_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalCannotInferTimeContext = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row120 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_Workflow_TimeContextRule_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}
enum C52ServiceRequestBoundary_TimeContextRule {
    static let sourceKind: ServiceRequestSourceKindV1 = .portableSubmission
    static let requesterAssertionType: ServiceRequestRequesterAssertionV1.Type = ServiceRequestRequesterAssertionV1.self
    static let contactAssertionType: ServiceRequestContactAssertionV1.Type = ServiceRequestContactAssertionV1.self
    static let requesterIdentityIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.requesterIdentityIsVerified
    static let contactAssertionWording: String = "SELF_ASSERTED_UNVERIFIED"
    static let urgencyIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.urgencyIsVerified
    static let cleartextIsReadableAndForwardable: Bool = PortableServiceRequestFormatBoundaryV1.submissionIsCleartext && PortableServiceRequestFormatBoundaryV1.invitationIsReadableAndForwardable
    static let providerContactPurposeSeparationRequired: Bool = true
    static let canonicalSourceBytesAreAuthoritative: Bool = true
    static let duplicateCandidatesAreDerived: Bool = !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityMayBecomeWorkspaceTruth: Bool = ServiceRequestNoncanonicalBoundaryV1.rawCapabilityIsWorkspaceTruth
    static let automaticWorkOrDuplicateActionPermitted: Bool = ServiceRequestNoncanonicalBoundaryV1.automaticWorkCreationPermitted || ServiceRequestNoncanonicalBoundaryV1.automaticDuplicateMergePermitted
    static let excludedSurfaces: [String] = ["REPORT", "SEARCH", "DIAGNOSTIC", "LIFECYCLE", "COMPATIBILITY", "BACKUP", "DELETE"]
}

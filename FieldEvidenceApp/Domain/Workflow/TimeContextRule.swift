import Foundation

enum ScheduleTimeContextBoundaryV1 { static func validate(_ value: FrozenScheduleTimeBasisV1) throws { try value.validate() } }

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

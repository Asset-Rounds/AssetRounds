import Foundation

enum LightingNightWorkflowFailureV1: Error, Equatable, Sendable {
    case incompatibleVersion
    case invalidValue
    case invalidDigest
    case wrongWorkspace
    case staleReference
    case duplicateIdentity
    case missingCanonicalSource
    case incompleteMeasurement
    case inconclusiveMeasurement
    case safetyStop
    case invalidSuccessor
    case forbiddenClaim
    case limitExceeded
    case revisionOverflow
}

enum LightingNightWorkflowLimitsV1 {
    static let maximumDeltas = LightingLimitsV1.maximumLuminaires
    static let maximumIssues = LightingLimitsV1.maximumLuminaires * 4
    static let maximumEvents = 2_048
    static let maximumRootGroups = 512
    static let maximumMediaPerDelta = 32
    static let maximumPartsPerRepair = 128
    static let maximumCanonicalBytes = 32 * 1_024 * 1_024

    static func next(_ value: UInt64) throws -> UInt64 {
        guard value < UInt64.max else { throw LightingNightWorkflowFailureV1.revisionOverflow }
        return value + 1
    }

    static func token(_ value: String, maximum: Int = 512) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value, value.utf8.count <= maximum else {
            throw LightingNightWorkflowFailureV1.invalidValue
        }
    }

    static func digest(_ value: String) throws {
        guard value.count == 64, value.allSatisfy({ $0.isHexDigit }), value == value.lowercased() else {
            throw LightingNightWorkflowFailureV1.invalidDigest
        }
    }
}

enum LightingNightWorkflowStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case nightInventoryRecorded = "NIGHT_INVENTORY_RECORDED"
    case repairRecorded = "REPAIR_RECORDED"
    case recheckRecorded = "RECHECK_RECORDED"
    case reopened = "REOPENED"
}

enum LightingExpectedControlStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case expectedOn = "EXPECTED_ON"
    case expectedOff = "EXPECTED_OFF"
    case noDeclaredExpectation = "NO_DECLARED_EXPECTATION"
    case unknown = "UNKNOWN"
}

enum LightingObservedControlStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case appearedOn = "APPEARED_ON"
    case appearedUnlit = "APPEARED_UNLIT"
    case partialOutput = "PARTIAL_OUTPUT"
    case intermittent = "INTERMITTENT"
    case unknown = "UNKNOWN"
    case notObserved = "NOT_OBSERVED"
}

enum LightingNightEnvironmentStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case observedPresent = "OBSERVED_PRESENT"
    case observedAbsent = "OBSERVED_ABSENT"
    case unknown = "UNKNOWN"
    case notObserved = "NOT_OBSERVED"
}

enum LightingNightMeasurementDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case notPerformed = "NOT_PERFORMED"
    case completeNoCriterionApplied = "COMPLETE_NO_CRITERION_APPLIED"
    case withinRecordedCriterion = "WITHIN_RECORDED_CRITERION"
    case potentialVariance = "POTENTIAL_VARIANCE"
    case inconclusiveUncertaintyCrossesCriterion = "INCONCLUSIVE_UNCERTAINTY_CROSSES_CRITERION"
}

enum LightingIssueRecheckRequirementV1: String, Codable, CaseIterable, Hashable, Sendable {
    case nightExpectedOnObservation = "NIGHT_EXPECTED_ON_OBSERVATION"
    case comparableQualifiedMeasurement = "COMPARABLE_QUALIFIED_MEASUREMENT"
    case qualifiedElectricalOrStructuralVerification = "QUALIFIED_ELECTRICAL_OR_STRUCTURAL_VERIFICATION"
    case relevantNightReobservation = "RELEVANT_NIGHT_REOBSERVATION"
}

enum LightingIssueRecheckResultV1: String, Codable, CaseIterable, Hashable, Sendable {
    case remainsOpen = "REMAINS_OPEN"
    case resolvedForRecordedScope = "RESOLVED_FOR_RECORDED_SCOPE"
    case inconclusive = "INCONCLUSIVE"
}

enum LightingIssueLifecycleActionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case repairRecorded = "REPAIR_RECORDED"
    case recheckRecorded = "RECHECK_RECORDED"
    case reopened = "REOPENED"
}

enum LightingNightClaimTierV1: String, Codable, CaseIterable, Hashable, Sendable {
    case observed = "OBSERVED"
    case measured = "MEASURED"
    case screened = "SCREENED"
    case qualifiedVerification = "QUALIFIED_VERIFICATION"
}

struct LightingNightDayBindingV1: Codable, Equatable, Hashable, Sendable {
    let workflowID: UUID
    let workflowRevision: UInt64
    private(set) var workflowSHA256: String
    let nightPlanID: UUID
    let nightPlanSHA256: String

    init(_ workflow: LightingDayInventoryWorkflowV1) throws {
        try workflow.validateIntrinsic()
        guard let plan = workflow.nightFollowupPlan else {
            throw LightingNightWorkflowFailureV1.staleReference
        }
        workflowID = workflow.workflowID
        workflowRevision = workflow.revision
        workflowSHA256 = workflow.workflowSHA256
        nightPlanID = plan.planID
        nightPlanSHA256 = plan.planSHA256
        try validate()
    }

    func validate() throws {
        try LightingLimitsV1.id(workflowID)
        try LightingLimitsV1.revision(workflowRevision)
        try LightingNightWorkflowLimitsV1.digest(workflowSHA256)
        try LightingLimitsV1.id(nightPlanID)
        try LightingNightWorkflowLimitsV1.digest(nightPlanSHA256)
    }
}

struct LightingNightSystemBindingV1: Codable, Equatable, Hashable, Sendable {
    let systemID: UUID
    let systemRevision: UInt64
    let systemSHA256: String
    let packageRelease: LightingPackageReleaseReferenceV1

    init(_ system: LightingSystemV1) throws {
        try system.validateIntrinsic()
        systemID = system.systemID
        systemRevision = system.revision
        systemSHA256 = system.systemSHA256
        packageRelease = system.packageRelease
        try validate()
    }

    func validate() throws {
        try LightingLimitsV1.id(systemID)
        try LightingLimitsV1.revision(systemRevision)
        try LightingNightWorkflowLimitsV1.digest(systemSHA256)
        try packageRelease.validate()
    }
}

struct LightingNightPlanFrontierV1: Codable, Equatable, Hashable, Sendable {
    let occurrence: LightingNightOccurrenceBindingV1
    let workPacket: WorkPacketManifestReferenceV1
    let readinessSourceSHA256: String
    let readinessManifestSHA256: String
    let readinessCheckedAt: Date

    init(_ plan: LightingNightFollowupPlanV1) throws {
        try plan.validate()
        occurrence = plan.occurrence
        workPacket = plan.workPacket
        readinessSourceSHA256 = plan.offlineReadinessSourceSHA256
        readinessManifestSHA256 = plan.offlineReadinessManifestSHA256
        readinessCheckedAt = plan.readinessCheckedAt
        try validate()
    }

    func validate() throws {
        try occurrence.validate()
        try workPacket.validate()
        try LightingNightWorkflowLimitsV1.digest(readinessSourceSHA256)
        try LightingNightWorkflowLimitsV1.digest(readinessManifestSHA256)
        try LightingLimitsV1.instant(readinessCheckedAt)
    }
}

struct LightingNightSafetyIntakeV1: Codable, Equatable, Sendable {
    let intake: LightingSafetyIntakeV1
    let nightPlanID: UUID
    let occurrenceEventID: UUID

    init(intake: LightingSafetyIntakeV1, nightPlan: LightingNightFollowupPlanV1) throws {
        self.intake = intake
        nightPlanID = nightPlan.planID
        occurrenceEventID = nightPlan.occurrence.eventID
        try validate(nightPlan: nightPlan)
    }

    var observationIsAuthorized: Bool { intake.observationIsAuthorized }

    func validate(nightPlan: LightingNightFollowupPlanV1) throws {
        try intake.validate()
        try nightPlan.validate()
        guard nightPlanID == nightPlan.planID,
              occurrenceEventID == nightPlan.occurrence.eventID,
              intake.workspaceID == nightPlan.workspaceID,
              intake.systemID == nightPlan.sourceSystemID,
              intake.systemRevision == nightPlan.sourceSystemRevision,
              intake.systemSHA256 == nightPlan.sourceSystemSHA256,
              intake.recordedAt >= nightPlan.createdAt else {
            throw LightingNightWorkflowFailureV1.staleReference
        }
    }
}

struct LightingQualifiedMeasurementReferenceV1: Codable, Equatable, Hashable, Sendable {
    let planID: UUID
    let planRevision: UInt64
    let planSHA256: String
    let seriesID: UUID
    let seriesRevision: UInt64
    let seriesSHA256: String
    let protocolReleaseID: UUID
    let protocolVersion: UInt64
    let protocolSHA256: String
    let instrumentID: UUID
    let instrumentRevision: UInt64
    let instrumentSHA256: String
    let calibrationSnapshotID: UUID
    let calibrationSHA256: String
    let criterionSHA256: String?
    let usedUnroundedCanonicalValues: Bool
    let completeSingleVersionGrid: Bool
    let uncertaintyCrossesCriterion: Bool
    let disposition: LightingNightMeasurementDispositionV1

    func validate() throws {
        try [planID, seriesID, protocolReleaseID, instrumentID, calibrationSnapshotID].forEach(LightingLimitsV1.id)
        try LightingLimitsV1.revision(planRevision)
        try LightingLimitsV1.revision(seriesRevision)
        try LightingLimitsV1.revision(protocolVersion)
        try LightingLimitsV1.revision(instrumentRevision)
        try [planSHA256, seriesSHA256, protocolSHA256, instrumentSHA256, calibrationSHA256].forEach(LightingNightWorkflowLimitsV1.digest)
        try criterionSHA256.map(LightingNightWorkflowLimitsV1.digest)
        guard usedUnroundedCanonicalValues, completeSingleVersionGrid,
              disposition != .notPerformed,
              (criterionSHA256 == nil) == (disposition == .completeNoCriterionApplied),
              uncertaintyCrossesCriterion == (disposition == .inconclusiveUncertaintyCrossesCriterion) else {
            throw LightingNightWorkflowFailureV1.incompleteMeasurement
        }
    }
}

struct LightingNightDeltaV1: Codable, Equatable, Sendable {
    let luminaireID: UUID
    let assetID: UUID
    let assetRevision: UInt64
    let zoneID: UUID
    let controlGroupID: UUID
    let observation: LightingObservationReferenceV1
    let expectedControl: LightingExpectedControlStateV1
    let observedControl: LightingObservedControlStateV1
    let issueKinds: [LightingIssueKindV1]
    let comparableMedia: [ContentReferenceV1]
    let temporaryLight: LightingNightEnvironmentStateV1
    let weatherContext: LightingNightEnvironmentStateV1
    let surfaceContext: LightingNightEnvironmentStateV1
    let measurement: LightingQualifiedMeasurementReferenceV1?
    let cameraBandingRecordedWithoutFlickerClaim: Bool
    let deltaSHA256: String

    init(luminaireID: UUID, assetID: UUID, assetRevision: UInt64, zoneID: UUID,
         controlGroupID: UUID, observation: LightingObservationReferenceV1,
         expectedControl: LightingExpectedControlStateV1,
         observedControl: LightingObservedControlStateV1,
         issueKinds: [LightingIssueKindV1], comparableMedia: [ContentReferenceV1],
         temporaryLight: LightingNightEnvironmentStateV1,
         weatherContext: LightingNightEnvironmentStateV1,
         surfaceContext: LightingNightEnvironmentStateV1,
         measurement: LightingQualifiedMeasurementReferenceV1?,
         cameraBandingRecordedWithoutFlickerClaim: Bool) throws {
        let issues = issueKinds.sorted()
        let media = comparableMedia.sorted { $0.contentID < $1.contentID }
        self.luminaireID = luminaireID; self.assetID = assetID; self.assetRevision = assetRevision
        self.zoneID = zoneID; self.controlGroupID = controlGroupID; self.observation = observation
        self.expectedControl = expectedControl; self.observedControl = observedControl
        self.issueKinds = issues; self.comparableMedia = media; self.temporaryLight = temporaryLight
        self.weatherContext = weatherContext; self.surfaceContext = surfaceContext
        self.measurement = measurement
        self.cameraBandingRecordedWithoutFlickerClaim = cameraBandingRecordedWithoutFlickerClaim
        deltaSHA256 = try LightingCanonicalCodecV1.sha256(Basis(luminaireID: luminaireID,
            assetID: assetID, assetRevision: assetRevision, zoneID: zoneID,
            controlGroupID: controlGroupID, observation: observation,
            expectedControl: expectedControl, observedControl: observedControl,
            issueKinds: issues, comparableMedia: media, temporaryLight: temporaryLight,
            weatherContext: weatherContext, surfaceContext: surfaceContext,
            measurement: measurement,
            cameraBandingRecordedWithoutFlickerClaim: cameraBandingRecordedWithoutFlickerClaim))
        try validate()
    }

    func validate() throws {
        try [luminaireID, assetID, zoneID, controlGroupID].forEach(LightingLimitsV1.id)
        try LightingLimitsV1.revision(assetRevision)
        try observation.validate()
        try measurement?.validate()
        let workspaceToken = observation.workspaceID.rawValue.uuidString.lowercased()
        guard observation.luminaireID == luminaireID,
              observation.assetID == assetID,
              observation.assetRevision == assetRevision,
              issueKinds == issueKinds.sorted(), Set(issueKinds).count == issueKinds.count,
              !comparableMedia.isEmpty,
              comparableMedia.count <= LightingNightWorkflowLimitsV1.maximumMediaPerDelta,
              comparableMedia == comparableMedia.sorted(by: { $0.contentID < $1.contentID }),
              Set(comparableMedia.map(\.contentID)).count == comparableMedia.count,
              comparableMedia.allSatisfy({ $0.workspaceID == workspaceToken }),
              !issueKinds.contains(.cameraBandingOnly) || cameraBandingRecordedWithoutFlickerClaim,
              observedControl != .intermittent || !issueKinds.contains(.cameraBandingOnly),
              deltaSHA256 == (try LightingCanonicalCodecV1.sha256(basis)) else {
            throw LightingNightWorkflowFailureV1.forbiddenClaim
        }
    }

    private var basis: Basis { .init(luminaireID: luminaireID, assetID: assetID,
        assetRevision: assetRevision, zoneID: zoneID, controlGroupID: controlGroupID,
        observation: observation, expectedControl: expectedControl, observedControl: observedControl,
        issueKinds: issueKinds, comparableMedia: comparableMedia, temporaryLight: temporaryLight,
        weatherContext: weatherContext, surfaceContext: surfaceContext, measurement: measurement,
        cameraBandingRecordedWithoutFlickerClaim: cameraBandingRecordedWithoutFlickerClaim) }
    private struct Basis: Codable {
        let luminaireID: UUID; let assetID: UUID; let assetRevision: UInt64; let zoneID: UUID
        let controlGroupID: UUID; let observation: LightingObservationReferenceV1
        let expectedControl: LightingExpectedControlStateV1; let observedControl: LightingObservedControlStateV1
        let issueKinds: [LightingIssueKindV1]; let comparableMedia: [ContentReferenceV1]
        let temporaryLight: LightingNightEnvironmentStateV1; let weatherContext: LightingNightEnvironmentStateV1
        let surfaceContext: LightingNightEnvironmentStateV1; let measurement: LightingQualifiedMeasurementReferenceV1?
        let cameraBandingRecordedWithoutFlickerClaim: Bool
    }
}

struct LightingIssueDetectionReferenceV1: Codable, Equatable, Hashable, Sendable {
    let issueID: UUID
    let issueRevision: UInt64
    let issueSHA256: String
    let kind: LightingIssueKindV1
    let observation: LightingObservationReferenceV1

    init(_ issue: LightingIssueV1) throws {
        try issue.validateIntrinsic()
        guard issue.disposition == .open else {
            throw LightingNightWorkflowFailureV1.forbiddenClaim
        }
        issueID = issue.issueID; issueRevision = issue.revision; issueSHA256 = issue.issueSHA256
        kind = issue.kind; observation = issue.observation
        try validate()
    }

    func validate() throws {
        try LightingLimitsV1.id(issueID); try LightingLimitsV1.revision(issueRevision)
        try LightingNightWorkflowLimitsV1.digest(issueSHA256); try observation.validate()
    }
}

struct LightingRepairPartV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let partID: String
    let manufacturer: String
    let model: String
    let exactConfigurationSHA256: String
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.partID < rhs.partID }
    func validate() throws {
        try LightingNightWorkflowLimitsV1.token(partID)
        try LightingNightWorkflowLimitsV1.token(manufacturer)
        try LightingNightWorkflowLimitsV1.token(model)
        try LightingNightWorkflowLimitsV1.digest(exactConfigurationSHA256)
    }
}

struct LightingRepairEventV1: Codable, Equatable, Sendable {
    let eventID: UUID
    let issue: LightingIssueDetectionReferenceV1
    let qualifiedActor: ActorSnapshotV1
    let workPerformed: String
    let parts: [LightingRepairPartV1]
    let settingsOrControlChangeSHA256: String?
    let beforeSystemRevision: UInt64
    let afterSystemRevision: UInt64
    let beforeEvidence: [ContentReferenceV1]
    let afterEvidence: [ContentReferenceV1]
    let outputDistributionCCTOrControlReviewRequired: Bool
    let predecessorEventID: UUID?
    let predecessorEventSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedAt: Date
    let eventSHA256: String

    func validate(workspaceID: WorkspaceID) throws {
        try LightingLimitsV1.id(eventID); try issue.validate(); try qualifiedActor.validate()
        try LightingNightWorkflowLimitsV1.token(workPerformed, maximum: 4_096)
        try parts.forEach { try $0.validate() }
        try settingsOrControlChangeSHA256.map(LightingNightWorkflowLimitsV1.digest)
        try LightingLimitsV1.revision(beforeSystemRevision); try LightingLimitsV1.revision(afterSystemRevision)
        try predecessorEventSHA256.map(LightingNightWorkflowLimitsV1.digest)
        try LightingLimitsV1.instant(recordedAt)
        let changed = beforeSystemRevision != afterSystemRevision || settingsOrControlChangeSHA256 != nil
        guard qualifiedActor.workspaceID == workspaceID,
              parts == parts.sorted(), Set(parts.map(\.partID)).count == parts.count,
              parts.count <= LightingNightWorkflowLimitsV1.maximumPartsPerRepair,
              !beforeEvidence.isEmpty, !afterEvidence.isEmpty,
              (beforeEvidence + afterEvidence).allSatisfy({ $0.workspaceID == workspaceID.rawValue.uuidString.lowercased() }),
              changed == outputDistributionCCTOrControlReviewRequired,
              (revision == 1) == (predecessorEventID == nil && predecessorEventSHA256 == nil) else {
            throw LightingNightWorkflowFailureV1.invalidValue
        }
        try LightingNightWorkflowLimitsV1.digest(eventSHA256)
    }
}

struct LightingRecheckEventV1: Codable, Equatable, Sendable {
    let eventID: UUID
    let issue: LightingIssueDetectionReferenceV1
    let requirement: LightingIssueRecheckRequirementV1
    let result: LightingIssueRecheckResultV1
    let screenedVarianceClaimSHA256: String?
    let nightObservation: LightingObservationReferenceV1?
    let measurement: LightingQualifiedMeasurementReferenceV1?
    let qualifiedVerificationSHA256: String?
    let evidence: [ContentReferenceV1]
    let predecessorEventID: UUID?
    let predecessorEventSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedBy: ActorSnapshotV1
    let recordedAt: Date
    let eventSHA256: String

    func validate(workspaceID: WorkspaceID, policy: LightingRepairRecheckPolicyV1) throws {
        try LightingLimitsV1.id(eventID); try issue.validate(); try nightObservation?.validate()
        try measurement?.validate(); try qualifiedVerificationSHA256.map(LightingNightWorkflowLimitsV1.digest)
        try screenedVarianceClaimSHA256.map(LightingNightWorkflowLimitsV1.digest)
        try predecessorEventSHA256.map(LightingNightWorkflowLimitsV1.digest)
        try recordedBy.validate(); try LightingLimitsV1.instant(recordedAt)
        try policy.validate(requirement: requirement, for: issue.kind,
                            hasScreenedVariance: screenedVarianceClaimSHA256 != nil)
        let closureComplete: Bool
        switch requirement {
        case .nightExpectedOnObservation, .relevantNightReobservation: closureComplete = nightObservation != nil
        case .comparableQualifiedMeasurement: closureComplete = measurement != nil
        case .qualifiedElectricalOrStructuralVerification: closureComplete = qualifiedVerificationSHA256 != nil
        }
        guard recordedBy.workspaceID == workspaceID, !evidence.isEmpty,
              evidence.allSatisfy({ $0.workspaceID == workspaceID.rawValue.uuidString.lowercased() }),
              result != .resolvedForRecordedScope || closureComplete,
              result != .resolvedForRecordedScope || measurement?.disposition != .inconclusiveUncertaintyCrossesCriterion,
              (revision == 1) == (predecessorEventID == nil && predecessorEventSHA256 == nil) else {
            throw LightingNightWorkflowFailureV1.forbiddenClaim
        }
        try LightingNightWorkflowLimitsV1.digest(eventSHA256)
    }
}

struct LightingReopenEventV1: Codable, Equatable, Sendable {
    let eventID: UUID
    let issue: LightingIssueDetectionReferenceV1
    let supersededRecheckEventID: UUID
    let supersededRecheckSHA256: String
    let recurrenceObservation: LightingObservationReferenceV1
    let evidence: [ContentReferenceV1]
    let mutationID: MutationIDV1
    let recordedBy: ActorSnapshotV1
    let recordedAt: Date
    let eventSHA256: String

    func validate(workspaceID: WorkspaceID) throws {
        try LightingLimitsV1.id(eventID); try issue.validate(); try LightingLimitsV1.id(supersededRecheckEventID)
        try LightingNightWorkflowLimitsV1.digest(supersededRecheckSHA256)
        try recurrenceObservation.validate(); try recordedBy.validate(); try LightingLimitsV1.instant(recordedAt)
        try LightingNightWorkflowLimitsV1.digest(eventSHA256)
        guard recordedBy.workspaceID == workspaceID, !evidence.isEmpty,
              evidence.allSatisfy({ $0.workspaceID == workspaceID.rawValue.uuidString.lowercased() }),
              recurrenceObservation.workspaceID == workspaceID else {
            throw LightingNightWorkflowFailureV1.wrongWorkspace
        }
    }

    func validate(workspaceID: WorkspaceID, supersededRecheck: LightingRecheckEventV1) throws {
        try validate(workspaceID: workspaceID)
        guard supersededRecheck.eventID == supersededRecheckEventID,
              supersededRecheck.eventSHA256 == supersededRecheckSHA256,
              supersededRecheck.issue.issueID == issue.issueID,
              supersededRecheck.issue.issueRevision == issue.issueRevision,
              supersededRecheck.issue.issueSHA256 == issue.issueSHA256,
              supersededRecheck.result == .resolvedForRecordedScope,
              recordedAt >= supersededRecheck.recordedAt else {
            throw LightingNightWorkflowFailureV1.invalidSuccessor
        }
    }
}

struct LightingRepairRecheckPolicyV1: Codable, Equatable, Sendable {
    static let currentVersion: UInt64 = 1
    let policyVersion: UInt64
    let policySHA256: String

    init(policyVersion: UInt64 = Self.currentVersion) throws {
        self.policyVersion = policyVersion
        policySHA256 = try LightingCanonicalCodecV1.sha256(Basis(policyVersion: policyVersion,
            mappings: LightingIssueKindV1.allCases.sorted().map { Mapping(kind: $0, requirement: Self.requirement(for: $0)) }))
        try validate()
    }

    func validate() throws {
        try LightingLimitsV1.revision(policyVersion)
        guard policyVersion == Self.currentVersion,
              policySHA256 == (try LightingCanonicalCodecV1.sha256(Basis(policyVersion: policyVersion,
                mappings: LightingIssueKindV1.allCases.sorted().map { Mapping(kind: $0, requirement: Self.requirement(for: $0)) }))) else {
            throw LightingNightWorkflowFailureV1.incompatibleVersion
        }
    }

    func validate(requirement: LightingIssueRecheckRequirementV1, for kind: LightingIssueKindV1) throws {
        try validate(requirement: requirement, for: kind, hasScreenedVariance: false)
    }

    func validate(requirement: LightingIssueRecheckRequirementV1, for kind: LightingIssueKindV1,
                  hasScreenedVariance: Bool) throws {
        try validate()
        let expected = hasScreenedVariance ? LightingIssueRecheckRequirementV1.comparableQualifiedMeasurement :
            Self.requirement(for: kind)
        guard requirement == expected else {
            throw LightingNightWorkflowFailureV1.forbiddenClaim
        }
    }

    static func requirement(for kind: LightingIssueKindV1) -> LightingIssueRecheckRequirementV1 {
        switch kind {
        case .appearedUnlit, .partialOutput, .observedIntermittent, .daylightEnergized, .controlUnknown:
            return .nightExpectedOnObservation
        case .visiblePotentialElectricalIndicator, .visiblePotentialEmergencyIndicator, .supportDamage:
            return .qualifiedElectricalOrStructuralVerification
        case .spillConcern, .glareConcern, .colorConcern, .alignmentConcern, .obstructionConcern,
             .lensConcern, .shieldConcern, .cameraBandingOnly:
            return .relevantNightReobservation
        }
    }

    private struct Mapping: Codable { let kind: LightingIssueKindV1; let requirement: LightingIssueRecheckRequirementV1 }
    private struct Basis: Codable { let policyVersion: UInt64; let mappings: [Mapping] }
}

struct IncidentRootCauseGroupV1: Codable, Equatable, Sendable {
    let groupID: UUID
    let supportedCauseCode: String
    let supportEvidenceSHA256: String
    let childIssues: [LightingIssueDetectionReferenceV1]
    let predecessorGroupID: UUID?
    let predecessorGroupSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedBy: ActorSnapshotV1
    let recordedAt: Date
    let groupSHA256: String

    func validate(workspaceID: WorkspaceID) throws {
        try LightingLimitsV1.id(groupID); try LightingNightWorkflowLimitsV1.token(supportedCauseCode)
        try LightingNightWorkflowLimitsV1.digest(supportEvidenceSHA256)
        try childIssues.forEach { try $0.validate() }
        try predecessorGroupSHA256.map(LightingNightWorkflowLimitsV1.digest)
        try recordedBy.validate(); try LightingLimitsV1.instant(recordedAt)
        try LightingNightWorkflowLimitsV1.digest(groupSHA256)
        guard childIssues.count >= 2, childIssues.count <= LightingNightWorkflowLimitsV1.maximumIssues,
              childIssues == childIssues.sorted(by: { $0.issueID.uuidString < $1.issueID.uuidString }),
              Set(childIssues.map(\.issueID)).count == childIssues.count,
              recordedBy.workspaceID == workspaceID,
              (revision == 1) == (predecessorGroupID == nil && predecessorGroupSHA256 == nil) else {
            throw LightingNightWorkflowFailureV1.invalidValue
        }
    }

}

struct LightingPatrolReferenceV1: Codable, Equatable, Hashable, Sendable {
    let round: RoundSessionReferenceV1
    let itemID: UUID
    let completion: RoundItemCompletionReferenceV1

    func validate(workspaceID: WorkspaceID) throws {
        try round.validate(); try LightingLimitsV1.id(itemID); try completion.validate()
        guard round.workspaceID == workspaceID else { throw LightingNightWorkflowFailureV1.wrongWorkspace }
    }

    func validate(roundSession: RoundSessionV1) throws {
        try validate(workspaceID: roundSession.workspaceID)
        try roundSession.validateIntrinsic()
        guard round == (try roundSession.reference),
              let item = roundSession.items.first(where: { $0.itemID == itemID }),
              item.completion == completion else {
            throw LightingNightWorkflowFailureV1.staleReference
        }
    }
}

struct LightingNightWorkflowClaimV1: Codable, Equatable, Sendable {
    let claimID: UUID
    let issueID: UUID?
    let tier: LightingNightClaimTierV1
    let textKey: String
    let sourceSHA256: String
    let limitationKey: String
    func validate() throws {
        try LightingLimitsV1.id(claimID); try issueID.map(LightingLimitsV1.id)
        try LightingNightWorkflowLimitsV1.token(textKey)
        try LightingNightWorkflowLimitsV1.digest(sourceSHA256)
        try LightingNightWorkflowLimitsV1.token(limitationKey)
        guard !textKey.localizedCaseInsensitiveContains("safe"),
              !textKey.localizedCaseInsensitiveContains("compliant"),
              !textKey.localizedCaseInsensitiveContains("code compliant") else {
            throw LightingNightWorkflowFailureV1.forbiddenClaim
        }
    }
}

struct LightingNightWorkflowV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let recordID: UUID
    let workflowID: UUID
    let workspaceID: WorkspaceID
    let system: LightingNightSystemBindingV1
    let day: LightingNightDayBindingV1
    let planFrontier: LightingNightPlanFrontierV1?
    let safety: LightingNightSafetyIntakeV1
    let deltas: [LightingNightDeltaV1]
    let repairPolicy: LightingRepairRecheckPolicyV1
    let repairs: [LightingRepairEventV1]
    let rechecks: [LightingRecheckEventV1]
    let reopens: [LightingReopenEventV1]
    let rootCauseGroups: [IncidentRootCauseGroupV1]
    let patrol: LightingPatrolReferenceV1?
    let claims: [LightingNightWorkflowClaimV1]
    let state: LightingNightWorkflowStateV1
    let supersedesRecordID: UUID?
    let predecessorSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedBy: ActorSnapshotV1
    let recordedAt: Date
    let workflowSHA256: String

    init(recordID: UUID, workflowID: UUID, workspaceID: WorkspaceID,
         system: LightingSystemV1, dayWorkflow: LightingDayInventoryWorkflowV1,
         safety: LightingNightSafetyIntakeV1, deltas: [LightingNightDeltaV1],
         repairPolicy: LightingRepairRecheckPolicyV1,
         repairs: [LightingRepairEventV1] = [], rechecks: [LightingRecheckEventV1] = [],
         reopens: [LightingReopenEventV1] = [], rootCauseGroups: [IncidentRootCauseGroupV1] = [],
         patrol: LightingPatrolReferenceV1? = nil, claims: [LightingNightWorkflowClaimV1] = [],
         state: LightingNightWorkflowStateV1, predecessor: Self? = nil,
         revision: UInt64, mutationID: MutationIDV1, recordedBy: ActorSnapshotV1,
         recordedAt: Date) throws {
        guard let nightPlan = dayWorkflow.nightFollowupPlan else { throw LightingNightWorkflowFailureV1.staleReference }
        let orderedDeltas = deltas.sorted { $0.luminaireID.uuidString < $1.luminaireID.uuidString }
        let orderedRepairs = repairs.sorted { $0.eventID.uuidString < $1.eventID.uuidString }
        let orderedRechecks = rechecks.sorted { $0.eventID.uuidString < $1.eventID.uuidString }
        let orderedReopens = reopens.sorted { $0.eventID.uuidString < $1.eventID.uuidString }
        let orderedGroups = rootCauseGroups.sorted { $0.groupID.uuidString < $1.groupID.uuidString }
        let orderedClaims = claims.sorted { $0.claimID.uuidString < $1.claimID.uuidString }
        let systemBinding = try LightingNightSystemBindingV1(system)
        let dayBinding = try LightingNightDayBindingV1(dayWorkflow)
        let planBinding = try LightingNightPlanFrontierV1(nightPlan)
        let supersededRecordID = predecessor?.recordID
        let priorSHA256 = predecessor?.workflowSHA256
        schemaVersion = Self.schemaVersion; self.recordID = recordID; self.workflowID = workflowID
        self.workspaceID = workspaceID; self.system = systemBinding; self.day = dayBinding
        planFrontier = planBinding; self.safety = safety; self.deltas = orderedDeltas
        self.repairPolicy = repairPolicy; self.repairs = orderedRepairs; self.rechecks = orderedRechecks
        self.reopens = orderedReopens; self.rootCauseGroups = orderedGroups; self.patrol = patrol
        self.claims = orderedClaims; self.state = state; supersedesRecordID = supersededRecordID
        predecessorSHA256 = priorSHA256; self.revision = revision
        self.mutationID = mutationID; self.recordedBy = recordedBy; self.recordedAt = recordedAt
        workflowSHA256 = try LightingCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, recordID: recordID, workflowID: workflowID,
            workspaceID: workspaceID, system: systemBinding, day: dayBinding,
            planFrontier: planBinding, safety: safety, deltas: orderedDeltas,
            repairPolicy: repairPolicy, repairs: orderedRepairs, rechecks: orderedRechecks,
            reopens: orderedReopens, rootCauseGroups: orderedGroups, patrol: patrol,
            claims: orderedClaims, state: state, supersedesRecordID: supersededRecordID,
            predecessorSHA256: priorSHA256, revision: revision, mutationID: mutationID,
            recordedBy: recordedBy, recordedAt: recordedAt))
        try validateIntrinsic()
        if let predecessor { try validateSuccessor(of: predecessor) }
    }

    func validateIntrinsic() throws {
        guard schemaVersion == Self.schemaVersion else { throw LightingNightWorkflowFailureV1.incompatibleVersion }
        try LightingLimitsV1.id(recordID); try LightingLimitsV1.id(workflowID)
        try system.validate(); try day.validate(); try planFrontier?.validate()
        try repairPolicy.validate(); try safety.intake.validate()
        try deltas.forEach { try $0.validate() }
        try repairs.forEach { try $0.validate(workspaceID: workspaceID) }
        try rechecks.forEach { try $0.validate(workspaceID: workspaceID, policy: repairPolicy) }
        try reopens.forEach { try $0.validate(workspaceID: workspaceID) }
        try rootCauseGroups.forEach { try $0.validate(workspaceID: workspaceID) }
        try patrol?.validate(workspaceID: workspaceID); try claims.forEach { try $0.validate() }
        try recordedBy.validate(); try LightingLimitsV1.instant(recordedAt)
        let IDs = deltas.map(\.luminaireID)
        let eventIDs = repairs.map(\.eventID) + rechecks.map(\.eventID) + reopens.map(\.eventID)
        let reopenedRecheckIDs = reopens.map(\.supersededRecheckEventID)
        let knownClaimSources = Set(deltas.map(\.observation.observationSHA256) +
            deltas.compactMap { $0.measurement?.seriesSHA256 } + repairs.map(\.eventSHA256) +
            rechecks.map(\.eventSHA256) + reopens.map(\.eventSHA256))
        let expectedState: LightingNightWorkflowStateV1 = !reopens.isEmpty ? .reopened :
            (!rechecks.isEmpty ? .recheckRecorded : (!repairs.isEmpty ? .repairRecorded : .nightInventoryRecorded))
        guard !deltas.isEmpty, deltas.count <= LightingNightWorkflowLimitsV1.maximumDeltas,
              deltas == deltas.sorted(by: { $0.luminaireID.uuidString < $1.luminaireID.uuidString }),
              Set(IDs).count == IDs.count,
              repairs.count + rechecks.count + reopens.count <= LightingNightWorkflowLimitsV1.maximumEvents,
              Set(eventIDs).count == eventIDs.count,
              Set(reopenedRecheckIDs).count == reopenedRecheckIDs.count,
              rootCauseGroups.count <= LightingNightWorkflowLimitsV1.maximumRootGroups,
              rootCauseGroups == rootCauseGroups.sorted(by: { $0.groupID.uuidString < $1.groupID.uuidString }),
              Set(rootCauseGroups.map(\.groupID)).count == rootCauseGroups.count,
              Set(claims.map(\.claimID)).count == claims.count,
              claims.allSatisfy({ knownClaimSources.contains($0.sourceSHA256) }),
              safety.intake.workspaceID == workspaceID,
              safety.intake.systemID == system.systemID,
              recordedBy.workspaceID == workspaceID,
              recordedBy.responsibility == .recordedBy,
              state == expectedState,
              (revision == 1) == (supersedesRecordID == nil && predecessorSHA256 == nil),
              planFrontier != nil,
              workflowSHA256 == (try LightingCanonicalCodecV1.sha256(basis)) else {
            throw LightingNightWorkflowFailureV1.invalidValue
        }
        guard safety.observationIsAuthorized else { throw LightingNightWorkflowFailureV1.safetyStop }
        try validateReopenBindings(against: rechecks)
    }

    func validate(system sourceSystem: LightingSystemV1,
                  dayWorkflow: LightingDayInventoryWorkflowV1) throws {
        try validateIntrinsic(); try sourceSystem.validateIntrinsic(); try dayWorkflow.validateIntrinsic()
        guard let sourcePlan = dayWorkflow.nightFollowupPlan else {
            throw LightingNightWorkflowFailureV1.staleReference
        }
        guard workspaceID == sourceSystem.workspaceID, workspaceID == dayWorkflow.workspaceID,
              system == (try LightingNightSystemBindingV1(sourceSystem)),
              day == (try LightingNightDayBindingV1(dayWorkflow)),
              planFrontier == (try LightingNightPlanFrontierV1(sourcePlan)) else {
            throw LightingNightWorkflowFailureV1.staleReference
        }
        try safety.validate(nightPlan: sourcePlan)
        guard Set(deltas.map(\.luminaireID)).isSubset(of: Set(plan.selectedLuminaireIDs)) else {
            throw LightingNightWorkflowFailureV1.staleReference
        }
    }

    func validateSuccessor(of predecessor: Self) throws {
        try predecessor.validateIntrinsic(); try validateIntrinsic()
        guard workspaceID == predecessor.workspaceID, workflowID == predecessor.workflowID,
              recordID != predecessor.recordID, supersedesRecordID == predecessor.recordID,
              predecessorSHA256 == predecessor.workflowSHA256,
              revision == (try LightingNightWorkflowLimitsV1.next(predecessor.revision)),
              mutationID != predecessor.mutationID,
              system == predecessor.system, day == predecessor.day,
              planFrontier == predecessor.planFrontier, safety == predecessor.safety,
              deltas == predecessor.deltas,
              predecessor.repairs.allSatisfy(repairs.contains),
              predecessor.rechecks.allSatisfy(rechecks.contains),
              predecessor.reopens.allSatisfy(reopens.contains),
              predecessor.rootCauseGroups.allSatisfy(rootCauseGroups.contains),
              predecessor.claims.allSatisfy(claims.contains),
              predecessor.patrol == nil || patrol == predecessor.patrol,
              repairs.count + rechecks.count + reopens.count + rootCauseGroups.count + claims.count >
                predecessor.repairs.count + predecessor.rechecks.count + predecessor.reopens.count +
                predecessor.rootCauseGroups.count + predecessor.claims.count else {
            throw LightingNightWorkflowFailureV1.invalidSuccessor
        }
        let priorReopenIDs = Set(predecessor.reopens.map(\.eventID))
        let newReopens = reopens.filter { !priorReopenIDs.contains($0.eventID) }
        try newReopens.forEach { reopen in
            guard let recheck = predecessor.rechecks.first(where: {
                $0.eventID == reopen.supersededRecheckEventID &&
                $0.eventSHA256 == reopen.supersededRecheckSHA256
            }) else { throw LightingNightWorkflowFailureV1.invalidSuccessor }
            try reopen.validate(workspaceID: workspaceID, supersededRecheck: recheck)
        }
    }

    private func validateReopenBindings(against acceptedRechecks: [LightingRecheckEventV1]) throws {
        try reopens.forEach { reopen in
            let matches = acceptedRechecks.filter {
                $0.eventID == reopen.supersededRecheckEventID &&
                $0.eventSHA256 == reopen.supersededRecheckSHA256
            }
            guard matches.count == 1, let recheck = matches.first else {
                throw LightingNightWorkflowFailureV1.invalidSuccessor
            }
            try reopen.validate(workspaceID: workspaceID, supersededRecheck: recheck)
        }
    }

    func rebound(recordID: UUID, workflowID: UUID, to workspaceID: WorkspaceID,
                 system: LightingSystemV1, dayWorkflow: LightingDayInventoryWorkflowV1,
                 safety: LightingNightSafetyIntakeV1, deltas: [LightingNightDeltaV1],
                 mutationID: MutationIDV1, recordedBy: ActorSnapshotV1,
                 recordedAt: Date) throws -> Self {
        try validateIntrinsic()
        guard workspaceID != self.workspaceID, system.workspaceID == workspaceID,
              dayWorkflow.workspaceID == workspaceID, recordedBy.workspaceID == workspaceID,
              deltas.allSatisfy({ $0.observation.workspaceID == workspaceID && $0.measurement == nil }) else {
            throw LightingNightWorkflowFailureV1.wrongWorkspace
        }
        return try Self(recordID: recordID, workflowID: workflowID, workspaceID: workspaceID,
            system: system, dayWorkflow: dayWorkflow, safety: safety, deltas: deltas,
            repairPolicy: repairPolicy, repairs: [], rechecks: [], reopens: [], rootCauseGroups: [],
            patrol: nil, claims: [], state: .nightInventoryRecorded, predecessor: nil, revision: 1,
            mutationID: mutationID, recordedBy: recordedBy, recordedAt: recordedAt)
    }

    private var basis: Basis {
        .init(schemaVersion: schemaVersion, recordID: recordID, workflowID: workflowID,
              workspaceID: workspaceID, system: system, day: day, planFrontier: planFrontier,
              safety: safety, deltas: deltas, repairPolicy: repairPolicy, repairs: repairs,
              rechecks: rechecks, reopens: reopens, rootCauseGroups: rootCauseGroups,
              patrol: patrol, claims: claims, state: state, supersedesRecordID: supersedesRecordID,
              predecessorSHA256: predecessorSHA256, revision: revision, mutationID: mutationID,
              recordedBy: recordedBy, recordedAt: recordedAt)
    }

    private struct Basis: Codable {
        let schemaVersion: Int; let recordID: UUID; let workflowID: UUID; let workspaceID: WorkspaceID
        let system: LightingNightSystemBindingV1; let day: LightingNightDayBindingV1
        let planFrontier: LightingNightPlanFrontierV1?; let safety: LightingNightSafetyIntakeV1
        let deltas: [LightingNightDeltaV1]; let repairPolicy: LightingRepairRecheckPolicyV1
        let repairs: [LightingRepairEventV1]; let rechecks: [LightingRecheckEventV1]
        let reopens: [LightingReopenEventV1]; let rootCauseGroups: [IncidentRootCauseGroupV1]
        let patrol: LightingPatrolReferenceV1?; let claims: [LightingNightWorkflowClaimV1]
        let state: LightingNightWorkflowStateV1; let supersedesRecordID: UUID?
        let predecessorSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1
        let recordedBy: ActorSnapshotV1; let recordedAt: Date
    }
}

struct LightingNightWorkflowAdmissionClosureV1: Codable, Equatable, Sendable {
    let system: LightingSystemV1
    let dayWorkflow: LightingDayInventoryWorkflowV1
    let observations: [LightingObservationV1]
    let issues: [LightingIssueV1]
    let admittedMeasurementSHA256s: [String]
    let patrolSessions: [RoundSessionV1]

    init(system: LightingSystemV1, dayWorkflow: LightingDayInventoryWorkflowV1,
         observations: [LightingObservationV1], issues: [LightingIssueV1],
         admittedMeasurementSHA256s: [String], patrolSessions: [RoundSessionV1]) {
        self.system = system; self.dayWorkflow = dayWorkflow
        self.observations = observations.sorted { $0.observationID.uuidString < $1.observationID.uuidString }
        self.issues = issues.sorted { $0.issueID.uuidString < $1.issueID.uuidString }
        self.admittedMeasurementSHA256s = admittedMeasurementSHA256s.sorted()
        self.patrolSessions = patrolSessions.sorted {
            if $0.sessionID != $1.sessionID { return $0.sessionID.uuidString < $1.sessionID.uuidString }
            return $0.revision < $1.revision
        }
    }

    func validate(_ workflow: LightingNightWorkflowV1) throws {
        try workflow.validate(system: system, dayWorkflow: dayWorkflow)
        try observations.forEach { try $0.validateIntrinsic() }
        try issues.forEach { try $0.validateIntrinsic() }
        try admittedMeasurementSHA256s.forEach(LightingNightWorkflowLimitsV1.digest)
        try patrolSessions.forEach { try $0.validateIntrinsic() }
        let observationRefs = Set(try observations.map { try LightingObservationReferenceV1($0) })
        let issueRefs = Set(try issues.map { try LightingIssueDetectionReferenceV1($0) })
        let usedIssues = Set(workflow.repairs.map(\.issue) + workflow.rechecks.map(\.issue) +
            workflow.reopens.map(\.issue) + workflow.rootCauseGroups.flatMap(\.childIssues))
        let usedMeasurements = Set(workflow.deltas.compactMap { $0.measurement?.seriesSHA256 } +
            workflow.rechecks.compactMap { $0.measurement?.seriesSHA256 })
        guard observations.allSatisfy({ $0.workspaceID == workflow.workspaceID }),
              issues.allSatisfy({ $0.workspaceID == workflow.workspaceID }),
              issues.allSatisfy({ $0.disposition == .open }),
              observations == observations.sorted(by: { $0.observationID.uuidString < $1.observationID.uuidString }),
              Set(observations.map(\.observationID)).count == observations.count,
              issues == issues.sorted(by: { $0.issueID.uuidString < $1.issueID.uuidString }),
              Set(issues.map(\.issueID)).count == issues.count,
              Set(workflow.deltas.map(\.observation)).isSubset(of: observationRefs),
              usedIssues.isSubset(of: issueRefs),
              usedMeasurements.isSubset(of: Set(admittedMeasurementSHA256s)),
              admittedMeasurementSHA256s == admittedMeasurementSHA256s.sorted(),
              Set(admittedMeasurementSHA256s).count == admittedMeasurementSHA256s.count,
              patrolSessions == patrolSessions.sorted(by: {
                if $0.sessionID != $1.sessionID { return $0.sessionID.uuidString < $1.sessionID.uuidString }
                return $0.revision < $1.revision
              }),
              Set(patrolSessions.map { "\($0.sessionID.uuidString):\($0.revision)" }).count == patrolSessions.count else {
            throw LightingNightWorkflowFailureV1.missingCanonicalSource
        }
        if let patrol = workflow.patrol {
            guard let session = patrolSessions.first(where: {
                $0.sessionID == patrol.round.sessionID && $0.revision == patrol.round.revision
            }) else { throw LightingNightWorkflowFailureV1.missingCanonicalSource }
            try patrol.validate(roundSession: session)
        }
    }
}

protocol LightingNightWorkflowSourceResolvingV1: Sendable {
    func validateCanonicalSources(for workflow: LightingNightWorkflowV1,
                                  admission: LightingNightWorkflowAdmissionClosureV1) async throws
}

struct LightingReportProjectionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let workflowID: UUID
    let workflowRevision: UInt64
    let workflowSHA256: String
    let system: LightingNightSystemBindingV1
    let day: LightingNightDayBindingV1
    let deltaCount: Int
    let openIssueIDs: [UUID]
    let resolvedForRecordedScopeIssueIDs: [UUID]
    let reopenedIssueIDs: [UUID]
    let rootCauseGroupIDs: [UUID]
    let measurementDispositions: [LightingNightMeasurementDispositionV1]
    let patrol: LightingPatrolReferenceV1?
    let claims: [LightingNightWorkflowClaimV1]
    let limitationKey: String
    let safetyOrComplianceConclusionAllowed: Bool

    init(_ workflow: LightingNightWorkflowV1) throws {
        try workflow.validateIntrinsic()
        let resolved = Set(workflow.rechecks.filter { $0.result == .resolvedForRecordedScope }.map(\.issue.issueID))
        let reopened = Set(workflow.reopens.map(\.issue.issueID))
        let all = Set(workflow.repairs.map(\.issue.issueID) + workflow.rechecks.map(\.issue.issueID) +
            workflow.reopens.map(\.issue.issueID) + workflow.rootCauseGroups.flatMap { $0.childIssues.map(\.issueID) })
        workspaceID=workflow.workspaceID;workflowID=workflow.workflowID;workflowRevision=workflow.revision
        workflowSHA256=workflow.workflowSHA256;system=workflow.system;day=workflow.day;deltaCount=workflow.deltas.count
        openIssueIDs=Array(all.subtracting(resolved).union(reopened)).sorted{$0.uuidString<$1.uuidString}
        resolvedForRecordedScopeIssueIDs=Array(resolved.subtracting(reopened)).sorted{$0.uuidString<$1.uuidString}
        reopenedIssueIDs=Array(reopened).sorted{$0.uuidString<$1.uuidString}
        rootCauseGroupIDs=workflow.rootCauseGroups.map(\.groupID).sorted{$0.uuidString<$1.uuidString}
        measurementDispositions=workflow.deltas.compactMap{ $0.measurement?.disposition }.sorted{$0.rawValue<$1.rawValue}
        patrol=workflow.patrol;claims=workflow.claims
        limitationKey="LIGHTING_VISUAL_FIELD_EVIDENCE_NOT_APP_ORIGINATED_SAFETY_OR_COMPLIANCE"
        safetyOrComplianceConclusionAllowed=false
        try validate()
    }

    func validate() throws {
        try LightingLimitsV1.id(workflowID); try LightingLimitsV1.revision(workflowRevision)
        try LightingNightWorkflowLimitsV1.digest(workflowSHA256)
        try system.validate(); try day.validate(); try patrol?.validate(workspaceID: workspaceID)
        try claims.forEach { try $0.validate() }
        guard deltaCount > 0,
              openIssueIDs == openIssueIDs.sorted(by: { $0.uuidString < $1.uuidString }),
              resolvedForRecordedScopeIssueIDs == resolvedForRecordedScopeIssueIDs.sorted(by: { $0.uuidString < $1.uuidString }),
              reopenedIssueIDs == reopenedIssueIDs.sorted(by: { $0.uuidString < $1.uuidString }),
              rootCauseGroupIDs == rootCauseGroupIDs.sorted(by: { $0.uuidString < $1.uuidString }),
              measurementDispositions == measurementDispositions.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(openIssueIDs).count == openIssueIDs.count,
              Set(resolvedForRecordedScopeIssueIDs).count == resolvedForRecordedScopeIssueIDs.count,
              Set(reopenedIssueIDs).count == reopenedIssueIDs.count,
              Set(rootCauseGroupIDs).count == rootCauseGroupIDs.count,
              Set(openIssueIDs).isDisjoint(with: Set(resolvedForRecordedScopeIssueIDs)),
              Set(reopenedIssueIDs).isSubset(of: Set(openIssueIDs)),
              claims == claims.sorted(by: { $0.claimID.uuidString < $1.claimID.uuidString }),
              Set(claims.map(\.claimID)).count == claims.count,
              limitationKey == "LIGHTING_VISUAL_FIELD_EVIDENCE_NOT_APP_ORIGINATED_SAFETY_OR_COMPLIANCE",
              !safetyOrComplianceConclusionAllowed else {
            throw LightingNightWorkflowFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case workspaceID, workflowID, workflowRevision, workflowSHA256, system, day, deltaCount
        case openIssueIDs, resolvedForRecordedScopeIssueIDs, reopenedIssueIDs, rootCauseGroupIDs
        case measurementDispositions, patrol, claims, limitationKey, safetyOrComplianceConclusionAllowed
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceID = try container.decode(WorkspaceID.self, forKey: .workspaceID)
        workflowID = try container.decode(UUID.self, forKey: .workflowID)
        workflowRevision = try container.decode(UInt64.self, forKey: .workflowRevision)
        workflowSHA256 = try container.decode(String.self, forKey: .workflowSHA256)
        system = try container.decode(LightingNightSystemBindingV1.self, forKey: .system)
        day = try container.decode(LightingNightDayBindingV1.self, forKey: .day)
        deltaCount = try container.decode(Int.self, forKey: .deltaCount)
        openIssueIDs = try container.decode([UUID].self, forKey: .openIssueIDs)
        resolvedForRecordedScopeIssueIDs = try container.decode([UUID].self, forKey: .resolvedForRecordedScopeIssueIDs)
        reopenedIssueIDs = try container.decode([UUID].self, forKey: .reopenedIssueIDs)
        rootCauseGroupIDs = try container.decode([UUID].self, forKey: .rootCauseGroupIDs)
        measurementDispositions = try container.decode(
            [LightingNightMeasurementDispositionV1].self, forKey: .measurementDispositions)
        patrol = try container.decodeIfPresent(LightingPatrolReferenceV1.self, forKey: .patrol)
        claims = try container.decode([LightingNightWorkflowClaimV1].self, forKey: .claims)
        limitationKey = try container.decode(String.self, forKey: .limitationKey)
        safetyOrComplianceConclusionAllowed = try container.decode(
            Bool.self, forKey: .safetyOrComplianceConclusionAllowed)
        try validate()
    }
}
